import LocalAuthentication
import SwiftUI
import VisionKit

/// Face ID (or the passcode) before letting a session do something: whoever picks up the unlocked phone shouldn't
/// approve a command on the Mac. Without a passcode on the device (the simulator) it just goes ahead.
func confirmOwner(_ reason: String, then go: @escaping () -> Void) {
    let ctx = LAContext()
    var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { go(); return }
    ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
        if ok { DispatchQueue.main.async(execute: go) }
    }
}

// MARK: - permission requests

/// The oldest request waiting on the Mac, at the bottom of the screen: allow, deny, or pick an answer.
struct PermissionCard: View {
    @ObservedObject var link: MacLink
    let p: PermissionRequest
    @SwiftUI.State private var picked: [String: Set<String>] = [:]
    @SwiftUI.State private var typed = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("✋ " + (p.label.isEmpty ? p.source : p.label)).font(.headline)
                Spacer()
                if link.permissions.count > 1 {
                    Text(String(format: tr("+%d esperando"), link.permissions.count - 1)).font(.caption).foregroundStyle(.secondary)
                }
            }
            if let q = p.question {
                Text(q.text).font(.subheadline)
                ForEach(q.options.indices, id: \.self) { i in
                    Button { link.decide(p, answer: q.options[i].label) } label: { option(q.options[i]) }
                        .buttonStyle(.bordered)
                }
                HStack {
                    TextField(tr("Outra resposta"), text: $typed).textFieldStyle(.roundedBorder)
                    Button(tr("Enviar")) { link.decide(p, answer: typed) }.disabled(typed.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            } else if !p.questions.isEmpty {
                ForEach(p.questions.indices, id: \.self) { qi in
                    let q = p.questions[qi]
                    Text(q.text).font(.subheadline)
                    FlowButtons(options: q.options.map(\.label), selected: picked[q.text] ?? []) { label in
                        var s = picked[q.text] ?? []
                        if q.multi { if s.contains(label) { s.remove(label) } else { s.insert(label) } } else { s = [label] }
                        picked[q.text] = s
                    }
                }
                Button(tr("Enviar respostas")) {
                    link.decide(p, answers: picked.mapValues { $0.sorted().joined(separator: ", ") })
                }
                .buttonStyle(.borderedProminent)
                .disabled(p.questions.contains { (picked[$0.text] ?? []).isEmpty })
            } else {
                Text(tr("quer usar") + " " + p.tool).font(.subheadline).foregroundStyle(.secondary)
                Text(p.summary).font(.system(.footnote, design: .monospaced)).lineLimit(6)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Button(role: .destructive) { link.decide(p, decision: "deny") } label: { Text(tr("Negar")).frame(maxWidth: .infinity) }
                        .buttonStyle(.bordered)
                    Button {
                        confirmOwner(tr("Permitir que a sessão use") + " " + p.tool) { link.decide(p, decision: "allow") }
                    } label: { Text(tr("Permitir")).frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
    }

    private func option(_ o: (label: String, about: String)) -> some View {
        VStack(alignment: .leading) {
            Text(o.label)
            if !o.about.isEmpty { Text(o.about).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A form's options, as toggles.
private struct FlowButtons: View {
    let options: [String]
    let selected: Set<String>
    let tap: (String) -> Void
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(options, id: \.self) { o in
                Button { tap(o) } label: {
                    Label(o, systemImage: selected.contains(o) ? "checkmark.circle.fill" : "circle").frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - a fish's card

/// What a session is doing, and the line to reply to it (typed into its terminal on the Mac) or to stop it.
struct FishCard: View {
    @ObservedObject var link: MacLink
    let id: String
    @SwiftUI.State private var text = ""
    @SwiftUI.State private var sending = false
    @SwiftUI.State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let d = link.fish[id] ?? [:]
        let can = Set(d["can"] as? [String] ?? [])
        let source = d["source"] as? String ?? "", entity = d["entity"] as? String ?? ""
        let waitingQuestion = link.permissions.contains { $0.source == source && $0.entity == entity && $0.question != nil }
        NavigationStack {
            Form {
                if d.isEmpty {
                    Text(tr("Essa sessão saiu do aquário.")).foregroundStyle(.secondary)
                } else {
                    Section {
                        LabeledContent(tr("Estado"), value: State(rawValue: d["state"] as? String ?? "").map(\.label) ?? "")
                        if let t = d["doing"] as? String, !t.isEmpty { LabeledContent(tr("Fazendo"), value: t) }
                        if let t = d["detail"] as? String, !t.isEmpty { Text(t).font(.footnote) }
                        if let b = d["branch"] as? String, !b.isEmpty { LabeledContent("Branch", value: b) }
                        if let m = d["model"] as? String, !m.isEmpty { LabeledContent(tr("Modelo"), value: m) }
                        if let w = (d["where"] as? [String: String])?["cwd"] { Text(w).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    }
                    if can.contains("reply") || waitingQuestion {
                        Section(tr("Responder")) {
                            TextField(tr("Escreva para a sessão"), text: $text, axis: .vertical).lineLimit(1...6)
                            Button(sending ? tr("Enviando…") : tr("Enviar")) {
                                sending = true
                                error = nil
                                link.reply(source: source, entity: entity, text: text) { e in
                                    sending = false
                                    if let e { error = e } else { text = ""; dismiss() }
                                }
                            }
                            .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                        }
                    }
                    if can.contains("stop") {
                        Section {
                            Button(tr("Interromper o agente"), role: .destructive) { link.stop(source: source, entity: entity) }
                        }
                    }
                }
            }
            .navigationTitle((d["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? d["label"] as? String ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Fechar")) { dismiss() } } }
        }
    }
}

// MARK: - pairing

/// No Mac yet: how to pair (the QR code in the Mac's Preferences, or its link pasted).
struct PairingView: View {
    @ObservedObject var link: MacLink
    @SwiftUI.State private var scanning = false
    @SwiftUI.State private var failed = false

    var body: some View {
        VStack(spacing: 18) {
            Text("Fishbots").font(.largeTitle.bold())
            Text(tr("No Mac, abra Preferências → Geral → Outros aparelhos, ligue o acesso e leia o código."))
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            if DataScannerViewController.isSupported {
                Button { scanning = true } label: { Label(tr("Ler o código"), systemImage: "qrcode.viewfinder").frame(maxWidth: .infinity) }
                    .buttonStyle(.borderedProminent).controlSize(.large)
            }
            Button {
                if let s = UIPasteboard.general.string, let u = URL(string: s.trimmingCharacters(in: .whitespacesAndNewlines)) { failed = !link.pair(u) } else { failed = true }
            } label: { Label(tr("Colar o link"), systemImage: "doc.on.clipboard").frame(maxWidth: .infinity) }
                .buttonStyle(.bordered).controlSize(.large)
            if failed { Text(tr("Isso não é um código do Fishbots.")).font(.footnote).foregroundStyle(.red) }
        }
        .padding(28)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .padding()
        .sheet(isPresented: $scanning) {
            QRScanner { s in
                if let u = URL(string: s), link.pair(u) { scanning = false } else { failed = true; scanning = false }
            }
            .ignoresSafeArea()
        }
    }
}

/// The camera, reading the first QR code it sees.
struct QRScanner: UIViewControllerRepresentable {
    let found: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let v = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], isHighlightingEnabled: true)
        v.delegate = context.coordinator
        try? v.startScanning()
        return v
    }

    func updateUIViewController(_ v: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(found) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let found: (String) -> Void
        var done = false
        init(_ found: @escaping (String) -> Void) { self.found = found }

        func dataScanner(_ s: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let b) in items {
                guard !done, let v = b.payloadStringValue else { continue }
                done = true
                s.stopScanning()
                found(v)
            }
        }
    }
}
