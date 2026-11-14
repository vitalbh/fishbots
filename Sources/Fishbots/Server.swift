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

    /// The tank's own: on 127.0.0.1 only, for hooks, `fishbots` and the screen saver.
    convenience init(port: UInt16, handler: @escaping (_ method: String, _ path: String, _ headers: [String: String], _ body: Data) -> (Int, Data)) throws {
        let params = NWParameters.tcp
        params.acceptLocalOnly = true
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        try self.init(listener: NWListener(using: params), local: true, handler: handler)
    }

    /// Any other listener (Remote.swift: other devices, over TLS with a pre-shared key). `local` false: the
    /// browser and Host checks are off, since whoever holds the key already proved who they are.
    init(listener: NWListener, local: Bool, handler: @escaping (_ method: String, _ path: String, _ headers: [String: String], _ body: Data) -> (Int, Data)) throws {
        self.listener = listener
        self.local = local
        self.handler = handler
        listener.newConnectionHandler = { [weak self] c in self?.accept(c) }
        listener.stateUpdateHandler = { state in
            if case .failed(let e) = state {
                FileHandle.standardError.write("fishbots: server stopped: \(e)\n".data(using: .utf8)!)
            }
        }
        listener.start(queue: .main)
    }

    func stop() { listener.cancel() }

    /// A response that stays open and carries events as they happen (Server-Sent Events: `event:` and `data:` lines).
    final class Stream {
        fileprivate let c: NWConnection
        private(set) var isOpen = true
        /// Called once, when the other side goes away or a write fails.
        var closed: (() -> Void)?

        fileprivate init(_ c: NWConnection) { self.c = c }

        func send(_ event: String, _ data: Data) {
            guard isOpen else { return }
            var out = Data("event: \(event)\n".utf8)
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
                out.append(Data("data: \(line)\n".utf8))
            }
            out.append(Data("\n".utf8))
            write(out)
        }

        /// A comment line: keeps proxies and the other side from taking a quiet stream for a dead one.
        func ping() { write(Data(": ping\n\n".utf8)) }

        fileprivate func write(_ d: Data) {
            c.send(content: d, completion: .contentProcessed { [weak self] e in if e != nil { self?.end() } })
        }

        func end() {
            guard isOpen else { return }
            isOpen = false
            c.cancel()
            closed?()
        }
    }

    /// Routes that answer with a stream: given the method and path, the function that takes the open stream.
    var stream: ((_ method: String, _ path: String, _ headers: [String: String]) -> ((Stream) -> Void)?)?
    private let local: Bool

    /// Looks at each connection once it's ready (its TLS done) before reading a request: false closes it.
    var admit: ((NWConnection) -> Bool)?

    private func accept(_ c: NWConnection) {
        guard let admit else {
            c.start(queue: .main)
            receive(c, Data(), continued: false)
            return
        }
        c.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                c.stateUpdateHandler = nil
                if admit(c) { self?.receive(c, Data(), continued: false) } else { c.cancel() }
            case .failed, .waiting:
                c.cancel()
            default: break
            }
        }
        c.start(queue: .main)
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
                if self.local && !self.allowed(headers) {
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
                    if let open = self.stream?(method, path, headers) { self.openStream(c, open); return }
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

    private func openStream(_ c: NWConnection, _ open: (Stream) -> Void) {
        let s = Stream(c)
        s.write(Data("HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n\r\n".utf8))
        c.stateUpdateHandler = { [weak s] state in
            switch state { case .failed, .cancelled: s?.end(); default: break }
        }
        // nothing more comes from the other side: a read that ends means it hung up
        func drain() {
            c.receive(minimumIncompleteLength: 1, maximumLength: 1 << 12) { [weak s] _, _, done, err in
                if done || err != nil { s?.end() } else { drain() }
            }
        }
        drain()
        open(s)
    }

    private func respond(_ c: NWConnection, _ status: Int, _ body: Data) {
        let reason = status == 200 ? "OK" : status == 404 ? "Not Found" : status == 400 ? "Bad Request" : status == 401 ? "Unauthorized" : status == 403 ? "Forbidden" : "Error"
        var out = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        out.append(body)
        c.send(content: out, completion: .contentProcessed { _ in c.cancel() })
    }
}
