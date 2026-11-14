import LocalAuthentication
import SwiftUI
import VisionKit

/// Face ID (or the passcode) before letting a session do something: whoever picks up the unlocked phone shouldn't
/// approve a command on the Mac. Without a passcode on the device (the simulator) it just goes ahead.
/// `within`: an approval this recent counts (replies ask once every few minutes; allowing a tool asks every time).
func confirmOwner(_ reason: String, within: TimeInterval = 0, then go: @escaping () -> Void) {
    if within > 0, let last = lastConfirmed, Date().timeIntervalSince(last) < within { go(); return }
    let ctx = LAContext()
    var err: NSError?
    guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { go(); return }
    ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
        if ok { DispatchQueue.main.async { lastConfirmed = Date(); go() } }
    }
}
private var lastConfirmed: Date?

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

/// A session's card, as on the Mac: the fish behind its window, how it is, what it asked, its last reply laid out
/// (ReplyText, the Mac's own), and the line to reply to it (typed into its terminal on the Mac) or to stop it.
/// Dark glass in the fish's color.
struct FishCard: View {
    @ObservedObject var link: MacLink
    let id: String
    @SwiftUI.State private var text = ""
    @SwiftUI.State private var sending = false
    @SwiftUI.State private var error: String?
    /// Its last reply, fetched when the card opens and again each time the session changes state.
    @SwiftUI.State private var said: NSAttributedString?
    @SwiftUI.State private var portrait: CGImage?
    @Environment(\.dismiss) private var dismiss

    private var fish: Fish? {
        let parts = id.split(separator: ":", maxSplits: 1).map(String.init)
        return parts.count == 2 ? link.mirror.tank.fish(source: parts[0], entity: parts[1]) : nil
    }

    private var tint: Color { fish.map { Color(red: Double($0.color.x), green: Double($0.color.y), blue: Double($0.color.z)) } ?? .teal }
    private var tintUI: UIColor { fish.map { UIColor(red: CGFloat($0.color.x), green: CGFloat($0.color.y), blue: CGFloat($0.color.z), alpha: 1) } ?? .systemTeal }

    var body: some View {
        let d = link.fish[id] ?? [:]
        let can = Set(d["can"] as? [String] ?? [])
        let source = d["source"] as? String ?? "", entity = d["entity"] as? String ?? ""
        let state = State(rawValue: d["state"] as? String ?? "")
        let question = link.permissions.first { $0.source == source && $0.entity == entity }
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if d.isEmpty {
                    Text(tr("Essa sessão saiu do aquário.")).foregroundStyle(.secondary).padding(.top, 30)
                } else {
                    header(d, state)
                    tags(d)
                    WaveLine().stroke(tint.opacity(0.35), lineWidth: 1).frame(height: 7)
                    if state == .busy, let t = d["doing"] as? String, !t.isEmpty {
                        Text("▸ " + t).font(.subheadline.weight(.medium)).foregroundStyle(tint)
                    }
                    if let c = (d["context"] as? NSNumber)?.doubleValue, c >= 0 { gauge(c) }
                    if let asked = question?.summary ?? (state == .waiting ? fish?.asked : nil), !asked.isEmpty {
                        Text("✋ " + asked).font(.subheadline.weight(.medium))
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.orange.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.35)))
                    }
                    if let said {
                        Label(tr("Última resposta"), systemImage: "text.bubble").font(.caption).foregroundStyle(.secondary)
                        RichText(text: said)
                    }
                    if can.contains("reply") || question?.question != nil {
                        WaveLine().stroke(tint.opacity(0.35), lineWidth: 1).frame(height: 7)
                        replyField(source, entity)
                    }
                    if can.contains("stop") {
                        Button(role: .destructive) { link.stop(source: source, entity: entity) } label: {
                            Label(tr("Interromper o agente"), systemImage: "stop.circle")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .padding(18)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(glass)
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2).symbolRenderingMode(.hierarchical) }
                .foregroundStyle(.secondary).padding(10)
        }
        .presentationBackground(.clear)
        .environment(\.colorScheme, .dark)
        .task(id: d["state"] as? String ?? "") { load(source: source, entity: entity) }
        .onAppear { drawPortrait() }
    }

    /// The fish behind its window, its name, and how it is.
    private func header(_ d: [String: Any], _ state: State?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                LinearGradient(colors: [Color(red: 0.09, green: 0.24, blue: 0.27), Color(red: 0.05, green: 0.14, blue: 0.17)], startPoint: .top, endPoint: .bottom)
                if let portrait { Image(decorative: portrait, scale: 1).resizable().scaledToFit().padding(2) }
                LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center)
            }
            .frame(width: 84, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(tint.opacity(0.8), lineWidth: 1.5))
            VStack(alignment: .leading, spacing: 3) {
                Text(title(d)).font(.system(.headline, design: .rounded)).lineLimit(2)
                let facts = [d["model"] as? String ?? "", d["branch"] as? String ?? ""].filter { !$0.isEmpty }
                if !facts.isEmpty { Text(facts.joined(separator: "  ·  ")).font(.caption).foregroundStyle(.tertiary) }
            }
            Spacer(minLength: 4)
            if let state {
                Text(state.label).font(.caption.weight(.semibold)).lineLimit(1)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .foregroundStyle(Self.color(state))
                    .background(Self.color(state).opacity(0.18), in: Capsule())
                    .padding(.trailing, 30)
            }
        }
    }

    private func title(_ d: [String: Any]) -> String {
        let t = d["title"] as? String ?? ""
        return t.isEmpty ? d["label"] as? String ?? "" : t
    }

    /// Where it runs: the agent, the folder.
    private func tags(_ d: [String: Any]) -> some View {
        let w = d["where"] as? [String: String] ?? [:]
        let folder = w["cwd"].map { ($0 as NSString).lastPathComponent }
        return HStack(spacing: 6) {
            if let s = d["source"] as? String { tag(s, "sparkles") }
            if let folder { tag(folder, "folder") }
            if w["rex_block"] != nil { tag("Rex", "rectangle.split.2x1") } else if w["tmux"] != nil { tag("tmux", "rectangle.split.2x1") }
        }
    }

    private func tag(_ t: String, _ icon: String) -> some View {
        Label(t, systemImage: icon).font(.caption).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7))
            .foregroundStyle(.secondary)
    }

    /// How full its context is, as water in a tube.
    private func gauge(_ c: Double) -> some View {
        let color: Color = c > 0.9 ? .red : c > 0.7 ? .orange : tint
        return HStack(spacing: 10) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.07))
                    Capsule().fill(LinearGradient(colors: [color, color.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, g.size.width * c))
                }
            }
            .frame(width: 120, height: 10)
            Text(String(format: tr("contexto %d%%"), Int((c * 100).rounded()))).font(.caption).foregroundStyle(c > 0.7 ? color : .secondary)
        }
    }

    private func replyField(_ source: String, _ entity: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .bottom) {
                TextField(tr("Escreva para a sessão"), text: $text, axis: .vertical).lineLimit(1...6)
                    .padding(10).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                Button {
                    // what's typed goes into the session's terminal, and an agent may act on it: the owner sends it
                    confirmOwner(tr("Enviar para a sessão no Mac"), within: 300) {
                        sending = true
                        error = nil
                        link.reply(source: source, entity: entity, text: text) { e in
                            sending = false
                            if let e { error = e } else { text = ""; dismiss() }
                        }
                    }
                } label: {
                    Image(systemName: sending ? "ellipsis.circle.fill" : "arrow.up.circle.fill").font(.title)
                }
                .tint(tint)
                .disabled(sending || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
        }
    }

    /// The Mac card's glass: dark, with the fish's color coming down from the top.
    private var glass: some View {
        ZStack {
            Color(red: 0.06, green: 0.07, blue: 0.1).opacity(0.94)
            LinearGradient(colors: [tint.opacity(0.26), tint.opacity(0.07), .clear], startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }

    static func color(_ s: State) -> Color {
        s == .error ? .red : s == .waiting ? .orange : s == .busy ? .teal : .secondary
    }

    /// The portrait is drawn once per look, in the background (the first one compiles the shader: a few seconds).
    private func drawPortrait() {
        guard let f = fish else { return }
        if let img = FishPortraits.image(for: f, ready: { drawPortrait() }) { portrait = img }
    }

    private func load(source: String, entity: String) {
        guard !source.isEmpty else { return }
        link.said(source: source, entity: entity) { text, markdown in
            guard let text, !text.isEmpty else { said = nil; return }
            said = ReplyText.attributed(text, markdown: markdown, tint: tintUI, size: 15)
        }
    }
}

/// The water's surface between the card's parts.
struct WaveLine: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let mid = r.midY, amp = r.height / 2 - 1
        p.move(to: CGPoint(x: r.minX, y: mid))
        var x = r.minX
        while x <= r.maxX {
            p.addLine(to: CGPoint(x: x, y: mid + sin(x / 18 * 2 * .pi) * amp))
            x += 2
        }
        return p
    }
}

/// An attributed text as UIKit lays it out (ReplyText's hanging lists and spacing), as tall as it needs to be.
struct RichText: UIViewRepresentable {
    let text: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        let v = UITextView()
        v.isEditable = false
        v.isScrollEnabled = false
        v.backgroundColor = .clear
        v.textContainerInset = .zero
        v.textContainer.lineFragmentPadding = 0
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    func updateUIView(_ v: UITextView, context: Context) { v.attributedText = text }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let w = proposal.width ?? 320
        return CGSize(width: w, height: uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height)
    }
}

// MARK: - a source's presences

/// A presence's card, as the Mac's source card: everything its source keeps in the tank (a CI's builds, a cluster's
/// pods…), the touched one first, each with how it is, what it says, and its link.
struct SourceSheet: View {
    @ObservedObject var link: MacLink
    let source: String
    let first: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let all = link.presences.filter { $0["source"] as? String == source }
            .sorted { a, b in (a["presence"] as? String == first ? 0 : 1, rank(a)) < (b["presence"] as? String == first ? 0 : 1, rank(b)) }
        NavigationStack {
            List {
                if all.isEmpty { Text(tr("Isso saiu do aquário.")).foregroundStyle(.secondary) }
                ForEach(all.indices, id: \.self) { i in row(all[i]) }
            }
            .navigationTitle(source)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button(tr("Fechar")) { dismiss() } } }
        }
    }

    /// Who needs you first.
    private func rank(_ p: [String: Any]) -> Int {
        switch p["state"] as? String { case "error": 0; case "waiting": 1; case "alert": 2; case "busy": 3; default: 4 }
    }

    private func row(_ p: [String: Any]) -> some View {
        let state = State(rawValue: p["state"] as? String ?? "")
        let url = (p["link"] as? String).flatMap(URL.init(string:)).flatMap { ["http", "https"].contains($0.scheme ?? "") ? $0 : nil }
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(p["label"] as? String ?? "").font(.headline)
                Spacer()
                if let state {
                    Text(state.label).font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .foregroundStyle(FishCard.color(state)).background(FishCard.color(state).opacity(0.18), in: Capsule())
                }
            }
            if let d = p["detail"] as? String, !d.isEmpty { Text(d).font(.subheadline).foregroundStyle(.secondary) }
            if let v = (p["value"] as? NSNumber)?.doubleValue, v >= 0 { ProgressView(value: min(1, v)) }
            if let url { Link(destination: url) { Label(url.host ?? url.absoluteString, systemImage: "arrow.up.right.square").font(.footnote) } }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - the resident assistant

/// The assistant's card, as on the Mac: the conversation (its answers laid out by ReplyText), what it's doing while
/// it thinks, what it asks to use, and the line to ask it something. It runs on the Mac; this only talks to it.
struct AssistantSheet: View {
    @ObservedObject var link: MacLink
    var open: (String) -> Void
    @SwiftUI.State private var text = ""
    @Environment(\.dismiss) private var dismiss

    private let tint = UIColor(red: 0.95, green: 0.62, blue: 0.3, alpha: 1)

    var body: some View {
        let a = link.assistant
        let turns = a["turns"] as? [[String: Any]] ?? []
        let thinking = a["thinking"] as? Bool == true
        NavigationStack {
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if a["on"] as? Bool != true {
                            Text(tr("O assistente está desligado no Mac (Preferências → Assistente).")).foregroundStyle(.secondary)
                        } else if turns.isEmpty {
                            Text(tr("Pergunte qualquer coisa sobre o aquário: quem está esperando, o que cada sessão fez, ou peça para ele cuidar de algo.")).foregroundStyle(.secondary)
                        }
                        ForEach(turns.indices, id: \.self) { i in turn(turns[i], last: i == turns.count - 1, thinking: thinking) }
                        if let r = a["request"] as? [String: Any] { request(r) }
                        Color.clear.frame(height: 1).id("end")
                    }
                    .padding()
                }
                .onChange(of: (turns.last?["a"] as? String)?.count ?? 0) { _, _ in withAnimation { scroll.scrollTo("end", anchor: .bottom) } }
                .onAppear { scroll.scrollTo("end", anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom) { field(thinking: thinking) }
            .navigationTitle(tr("assistente"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { link.assistant("new") } label: { Image(systemName: "square.and.pencil") }.disabled(turns.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) { Button(tr("Fechar")) { dismiss() } }
            }
        }
        .onAppear { link.assistant("seen") }
    }

    private func turn(_ t: [String: Any], last: Bool, thinking: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let q = t["q"] as? String, !q.isEmpty {
                Text(q).font(.callout).padding(10)
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            let answer = t["a"] as? String ?? ""
            if !answer.isEmpty { RichText(text: ReplyText.attributed(answer, markdown: true, tint: tint, size: 15)) }
            if last && thinking {
                let doing = t["doing"] as? String ?? ""
                Label(doing.isEmpty ? tr("pensando…") : doing, systemImage: "ellipsis").font(.footnote).foregroundStyle(.secondary)
            }
            if t["failed"] as? Bool == true { Text(tr("não consegui responder")).font(.footnote).foregroundStyle(.red) }
            let mentions = t["mentions"] as? [String] ?? []
            if !mentions.isEmpty {
                HStack {
                    ForEach(mentions.prefix(4), id: \.self) { id in
                        Button((link.fish[id]?["label"] as? String) ?? id) { open(id) }.buttonStyle(.bordered).font(.caption)
                    }
                }
            }
        }
    }

    /// It wants to use something: allow once, always (the rules it offers, narrowest first), or deny.
    private func request(_ r: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("✋ " + tr("quer usar") + " " + (r["tool"] as? String ?? "")).font(.subheadline.weight(.medium))
            if let s = r["summary"] as? String, !s.isEmpty {
                Text(s).font(.system(.footnote, design: .monospaced)).lineLimit(5)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Button(tr("Negar"), role: .destructive) { link.assistant("decide", ["allow": false]) }.buttonStyle(.bordered)
                Button(tr("Permitir")) { confirmOwner(tr("Permitir que o assistente use") + " " + (r["tool"] as? String ?? "")) { link.assistant("decide", ["allow": true]) } }
                    .buttonStyle(.borderedProminent)
            }
            ForEach(r["always"] as? [[String: String]] ?? [], id: \.self) { k in
                Button(String(format: tr("Sempre permitir %@"), k["label"] ?? "")) {
                    confirmOwner(tr("Permitir sempre")) { link.assistant("decide", ["allow": true, "always": k["key"] ?? ""]) }
                }
                .font(.footnote)
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 12))
    }

    private func field(thinking: Bool) -> some View {
        HStack(alignment: .bottom) {
            TextField(tr("Pergunte ao assistente"), text: $text, axis: .vertical).lineLimit(1...5)
                .padding(10).background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            if thinking {
                Button { link.assistant("stop") } label: { Image(systemName: "stop.circle.fill").font(.title) }.tint(.red)
            } else {
                Button {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !t.isEmpty else { return }
                    link.assistant("ask", ["text": t])
                    text = ""
                } label: { Image(systemName: "arrow.up.circle.fill").font(.title) }
                .tint(Color(tint))
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}

// MARK: - a new session

/// "Nova sessão": what it should do, with which agent, in which folder of the Mac. It runs there, in a terminal,
/// like one from the eggs; its fish shows up here once it's born.
struct NewSessionSheet: View {
    @ObservedObject var link: MacLink
    @SwiftUI.State private var task = ""
    @SwiftUI.State private var agents: [(id: String, name: String)] = []
    @SwiftUI.State private var agent = ""
    @SwiftUI.State private var folders: [String] = []
    @SwiftUI.State private var folder = ""
    @SwiftUI.State private var typed = ""
    @SwiftUI.State private var canOpen = true
    @SwiftUI.State private var loaded = false
    @SwiftUI.State private var opening = false
    @SwiftUI.State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private var where_: String { folder == "…" ? typed.trimmingCharacters(in: .whitespaces) : folder }

    var body: some View {
        NavigationStack {
            Form {
                if !loaded {
                    ProgressView()
                } else if !canOpen || agents.isEmpty {
                    Text(tr("O aquário abre sessões no Rex, no Herdr, no iTerm ou no tmux, e nenhum deles está instalado.")).foregroundStyle(.secondary)
                } else {
                    Section(tr("O que fazer")) {
                        TextField(tr("Descreva a tarefa (ou deixe em branco)"), text: $task, axis: .vertical).lineLimit(3...8)
                    }
                    Section {
                        Picker(tr("Agente"), selection: $agent) { ForEach(agents, id: \.id) { Text($0.name).tag($0.id) } }
                        Picker(tr("Pasta"), selection: $folder) {
                            ForEach(folders, id: \.self) { Text(($0 as NSString).abbreviatingWithTildeInPath).tag($0) }
                            Text(tr("Outra…")).tag("…")
                        }
                        if folder == "…" {
                            TextField("~/Dev/projeto", text: $typed).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .font(.body.monospaced())
                        }
                    } footer: {
                        Text(tr("Ela roda no Mac, num terminal de lá, como uma aberta pelos ovos.")).font(.footnote)
                    }
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle(tr("Nova sessão"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(tr("Cancelar")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(opening ? tr("Abrindo…") : tr("Abrir")) { open() }
                        .disabled(!loaded || !canOpen || opening || agent.isEmpty || where_.isEmpty)
                }
            }
        }
        .task { load() }
    }

    private func load() {
        link.spawnOptions { o in
            loaded = true
            guard let o else { error = tr("não achei o Mac"); return }
            agents = (o["agents"] as? [[String: String]] ?? []).compactMap { d in d["id"].map { ($0, d["name"] ?? $0) } }
            agent = o["agent"] as? String ?? agents.first?.id ?? ""
            if !agents.contains(where: { $0.id == agent }) { agent = agents.first?.id ?? "" }
            folders = o["folders"] as? [String] ?? []
            folder = folders.first ?? "…"
            canOpen = o["canOpen"] as? Bool ?? true
        }
    }

    /// It starts an agent on the Mac: the owner asks for it.
    private func open() {
        confirmOwner(tr("Abrir uma sessão no Mac")) {
            opening = true
            error = nil
            link.spawn(agent: agent, cwd: where_, task: task) { e in
                opening = false
                if let e { error = e } else { link.notice = tr("Sessão aberta no Mac"); dismiss() }
            }
        }
    }
}

// MARK: - while you were away

/// What happened since the app last looked: how many finished, broke, waited, and the latest of each.
struct AwayCard: View {
    @ObservedObject var link: MacLink
    var open: (String) -> Void

    var body: some View {
        let items = Array(link.away.suffix(6).reversed())
        let count = { (k: String) in link.away.filter { $0["kind"] as? String == k }.count }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(link.awayTitle).font(.headline)
                Spacer()
                Button { link.away = [] } label: { Image(systemName: "xmark.circle.fill").font(.title3).symbolRenderingMode(.hierarchical) }
                    .foregroundStyle(.secondary)
            }
            Text([count("done") > 0 ? String(format: tr("%d terminaram"), count("done")) : nil,
                  count("error") > 0 ? String(format: tr("%d com erro"), count("error")) : nil,
                  count("waiting") > 0 ? String(format: tr("%d esperaram você"), count("waiting")) : nil,
                  count("merge") > 0 ? String(format: tr("%d merges"), count("merge")) : nil].compactMap { $0 }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(.secondary)
            ForEach(items.indices, id: \.self) { i in
                let e = items[i]
                Button { if let f = e["fish"] as? String, !f.isEmpty { open(f) } } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(icon(e["kind"] as? String)).frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(line(e)).font(.subheadline.weight(.medium)).lineLimit(1)
                            if let said = e["said"] as? String, !said.isEmpty {
                                Text(said).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
    }

    private func icon(_ kind: String?) -> String {
        switch kind { case "done": "✓"; case "error": "✗"; case "waiting": "✋"; case "merge": "⇢"; default: "·" }
    }

    private func line(_ e: [String: Any]) -> String {
        let label = e["label"] as? String ?? ""
        let what = [e["title"], e["task"]].compactMap { $0 as? String }.first { !$0.isEmpty }
        return what.map { label + " — " + $0 } ?? label
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
