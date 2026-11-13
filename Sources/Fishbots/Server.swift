import Foundation
import Network

/// Minimal HTTP server, only on 127.0.0.1. Each request is answered and the connection closes.
final class Server {
    private let listener: NWListener
    private let handler: (String, String, [String: String], Data) -> (Int, Data)
    /// Routes that reply later (e.g. a permission request waiting for the click). Returns true if it will reply through `reply`.
    /// Each is asked in turn; the first to take the request answers it.
    var deferred: [(_ method: String, _ path: String, _ headers: [String: String], _ body: Data,
                    _ reply: @escaping (Int, Data) -> Void) -> Bool] = []

    init(port: UInt16, handler: @escaping (_ method: String, _ path: String, _ headers: [String: String], _ body: Data) -> (Int, Data)) throws {
        let params = NWParameters.tcp
        params.acceptLocalOnly = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        listener = try NWListener(using: params)
        self.handler = handler
        listener.newConnectionHandler = { [weak self] c in self?.accept(c) }
        listener.stateUpdateHandler = { state in
            if case .failed(let e) = state {
                FileHandle.standardError.write("fishbots: server stopped: \(e)\n".data(using: .utf8)!)
            }
        }
        listener.start(queue: .main)
    }

    private func accept(_ c: NWConnection) {
        c.start(queue: .main)
        receive(c, Data(), continued: false)
    }

    private func receive(_ c: NWConnection, _ acc: Data, continued: Bool) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, err in
            guard let self else { return }
            var buf = acc
            if let data { buf.append(data) }
            var sentContinue = continued
            if let r = buf.range(of: Data("\r\n\r\n".utf8)) {
                let head = String(decoding: buf[buf.startIndex..<r.lowerBound], as: UTF8.self)
                let lines = head.components(separatedBy: "\r\n")
                let parts = lines.first?.split(separator: " ") ?? []
                let method = parts.count > 0 ? String(parts[0]) : ""
                let path = parts.count > 1 ? String(parts[1]) : "/"
                var len = 0
                var expect = false
                var headers: [String: String] = [:]
                for l in lines.dropFirst() {
                    let kv = l.split(separator: ":", maxSplits: 1)
                    guard kv.count == 2 else { continue }
                    let k = kv[0].lowercased()
                    let v = kv[1].trimmingCharacters(in: .whitespaces)
                    if !v.isEmpty { headers[k] = v }
                    if k == "content-length" { len = Int(v) ?? 0 }
                    if k == "expect" && v.lowercased() == "100-continue" { expect = true }
                }
                if !self.allowed(headers) {
                    self.respond(c, 403, Data(#"{"error":"local clients only (curl, hooks), not browsers"}"#.utf8))
                    return
                }
                if len > 8 << 20 {
                    self.respond(c, 413, Data(#"{"error":"too large"}"#.utf8))
                    return
                }
                let have = buf.distance(from: r.upperBound, to: buf.endIndex)
                if have >= len || done {
                    let end = buf.index(r.upperBound, offsetBy: min(have, len))
                    let body = Data(buf[r.upperBound..<end])
                    let later: (Int, Data) -> Void = { [weak self] st, data in
                        DispatchQueue.main.async { self?.respond(c, st, data) }
                    }
                    if self.deferred.contains(where: { $0(method, path, headers, body, later) }) { return }
                    let (status, resp) = self.handler(method, path, headers, body)
                    self.respond(c, status, resp)
                    return
                }
                if expect && !sentContinue {
                    sentContinue = true
                    c.send(content: Data("HTTP/1.1 100 Continue\r\n\r\n".utf8), completion: .idempotent)
                }
            }
            if done || err != nil || buf.count > 9 << 20 { c.cancel(); return }
            self.receive(c, buf, continued: sentContinue)
        }
    }

    /// Blocks web pages. Legitimate clients (hooks via curl, bin/fishbots, the screensaver via URLSession)
    /// don't send Origin or Sec-Fetch-*; a browser sends them on every cross-origin POST and on fetch. A Host other than
    /// 127.0.0.1/localhost catches DNS rebinding (any domain pointed at 127.0.0.1 reading /state).
    /// Local processes are deliberately not blocked: they already read the conversations straight from disk.
    private func allowed(_ headers: [String: String]) -> Bool {
        if headers["origin"] != nil { return false }
        if let s = headers["sec-fetch-site"], s != "none" { return false }
        if let h = headers["host"]?.lowercased() {
            let name = h.hasPrefix("[") ? String(h.prefix { $0 != "]" }) + "]"
                                        : String(h.split(separator: ":", maxSplits: 1).first ?? "")
            if !["127.0.0.1", "localhost", "[::1]"].contains(name) { return false }
        }
        return true
    }

    private func respond(_ c: NWConnection, _ status: Int, _ body: Data) {
        let reason = status == 200 ? "OK" : status == 404 ? "Not Found" : status == 400 ? "Bad Request" : status == 401 ? "Unauthorized" : status == 403 ? "Forbidden" : "Error"
        var out = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        out.append(body)
        c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
    }
}
