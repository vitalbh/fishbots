import AppKit
import SwiftUI

/// The first launch: what the aquarium is, and the one thing it needs before anything swims in it, the agents
/// connected (AgentHooks.swift). It looks like the fish's cards (dark glass, bubbles, each agent's fish behind a round
/// window), not like a settings form. Shown once, while no agent has the aquarium's hooks; the app menu opens it again.
///
/// What would make macOS ask for a permission is off until it's turned on here, with what it is and what macOS will
/// ask (the music fish: controlling Spotify or Music). The rest of macOS's permissions are asked when each feature is
/// first used.
final class WelcomeWindow {
    private var window: NSWindow?
    /// "Parear o iPhone…": the preferences, where the pairing is.
    var showPairing: () -> Void = {}
    /// "Ver uma demonstração": demo mode on.
    var showDemo: () -> Void = {}

    /// On launch: only the first time, and only if no agent is connected yet (one from a clone counts).
    var due: Bool { !UserDefaults.standard.bool(forKey: "welcomed") && AgentHooks.connected().isEmpty }

    func show() {
        if window == nil {
            let view = WelcomeView(pairing: { [weak self] in self?.showPairing() },
                                   demo: { [weak self] in self?.showDemo(); self?.close() },
                                   done: { [weak self] in self?.close() })
            let host = NSHostingController(rootView: view)
            let w = EscClosingWindow(contentViewController: host)
            w.styleMask = [.titled, .closable, .fullSizeContentView]
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.appearance = NSAppearance(named: .darkAqua)
            w.backgroundColor = Self.backdrop
            w.isReleasedWhenClosed = false
            // above the tank, which may float over every window (Flutuar sobre as janelas)
            w.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
            w.setContentSize(host.view.fittingSize)
            w.center()
            window = w
        }
        UserDefaults.standard.set(true, forKey: "welcomed")
        window?.title = tr("Boas-vindas ao Fishbots")
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }

    /// The cards' dark water.
    static let backdrop = NSColor(red: 0.04, green: 0.082, blue: 0.105, alpha: 1)
    static let tint = NSColor(red: 0.35, green: 0.78, blue: 0.82, alpha: 1)
}

/// The cards' glass behind SwiftUI: the water, its light and the bubbles (CardGlass.swift).
private struct Glass: NSViewRepresentable {
    func makeNSView(context: Context) -> GlassView { GlassView(backdrop: WelcomeWindow.backdrop, tint: WelcomeWindow.tint) }
    func updateNSView(_ v: GlassView, context: Context) {}
}

/// A fish behind a round window, as on its card.
private struct RoundWindow: View {
    let image: CGImage?
    let tint: Color
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.09, green: 0.24, blue: 0.27), Color(red: 0.05, green: 0.14, blue: 0.17)],
                           startPoint: .top, endPoint: .bottom)
            if let image { Image(decorative: image, scale: 2).resizable().aspectRatio(contentMode: .fill) }
            LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center)
        }
        .frame(width: 66, height: 44)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.6), lineWidth: 1.5))
    }
}

private struct WelcomeView: View {
    let pairing: () -> Void
    let demo: () -> Void
    let done: () -> Void

    @SwiftUI.State private var tick = 0
    @SwiftUI.State private var problem: String?
    @SwiftUI.State private var portraits: [String: CGImage] = [:]
    @SwiftUI.State private var music = NowPlaying.enabled

    /// Each agent's fish and color, as the tank draws it.
    private static let looks: [String: (kind: String, color: SIMD3<Float>)] = [
        "claude-code": ("oval", SIMD3(0.95, 0.55, 0.32)), "codex": ("stingray", SIMD3(0.35, 0.75, 0.9)),
        "cursor": ("angelfish", SIMD3(0.7, 0.55, 0.95)), "antigravity": ("slender", SIMD3(0.4, 0.6, 1)),
        "opencode": ("needlefish", SIMD3(0.45, 0.85, 0.55)), "music": ("betta", SIMD3(0.85, 0.35, 0.6)),
    ]

    var body: some View {
        let _ = tick
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(tr("Seus agentes viram peixes"))
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(tr("Cada sessão de um agente de código vira um peixe: você vê quem trabalha, quem terminou e quem espera você, e ouve quando algo muda."))
                    .font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 14)

            heading(tr("Conecte seus agentes"))
            VStack(spacing: 8) {
                ForEach(AgentHooks.agents, id: \.id) { agentRow($0) }
            }
            if let problem { Text(problem).font(.footnote).foregroundStyle(.orange) }

            heading(tr("Se quiser"))
            VStack(spacing: 8) {
                box {
                    HStack(spacing: 12) {
                        RoundWindow(image: portraits["music"], tint: color("music"))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("Peixe da música")).font(.system(size: 13, weight: .medium))
                            Text(tr("Quando o Spotify ou o Música toca, um betta dança no aquário com o nome da faixa. O macOS vai pedir para o Fishbots ver o que esses apps tocam."))
                                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 8)
                        Toggle("", isOn: Binding(get: { music }, set: { music = $0; NowPlaying.enabled = $0 }))
                            .toggleStyle(.switch).labelsHidden()
                    }
                }
                box {
                    HStack(spacing: 12) {
                        Image(systemName: "iphone").font(.system(size: 22)).frame(width: 66, height: 44)
                            .foregroundStyle(Color(nsColor: WelcomeWindow.tint))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(tr("No iPhone")).font(.system(size: 13, weight: .medium))
                            Text(tr("Veja o aquário e responda às sessões pelo celular."))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 8)
                        pill(tr("Parear…"), filled: false, action: pairing)
                    }
                }
            }

            Text(tr("O macOS pede as outras permissões na hora em que cada coisa é usada: o microfone para responder falando, a automação para ir até o terminal de uma sessão, as notificações para avisar quando alguém espera você."))
                .font(.system(size: 11)).foregroundStyle(.tertiary).fixedSize(horizontal: false, vertical: true)

            HStack {
                pill(tr("Ver uma demonstração"), filled: false, action: demo)
                Spacer()
                pill(tr("Pronto"), filled: true, action: done).keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .frame(width: 540)
        .background(Glass())
        .preferredColorScheme(.dark)
        .task { await drawPortraits() }
    }

    private func agentRow(_ agent: AgentHooks.Agent) -> some View {
        let connected = AgentHooks.isConnected(agent.id), present = AgentHooks.present(agent.id)
        return box {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    RoundWindow(image: portraits[agent.id], tint: color(agent.id))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: agent.name).font(.system(size: 13, weight: .medium))
                        Text(connected ? tr("conectado") : present ? tr("encontrado neste Mac") : tr("não encontrado neste Mac"))
                            .font(.system(size: 11)).foregroundStyle(connected ? Color.green : .secondary)
                    }
                    Spacer(minLength: 8)
                    if connected {
                        pill(tr("Desconectar"), filled: false) { AgentHooks.disconnect(agent.id); tick += 1 }
                    } else {
                        pill(tr("Conectar"), filled: present) { problem = AgentHooks.connect(agent.id); tick += 1 }
                    }
                }
                if connected && agent.permissions {
                    Toggle(isOn: Binding(get: { AgentHooks.answersPermissions(agent.id) }, set: { on in
                        if on { problem = AgentHooks.connect(agent.id, permissions: true) } else { AgentHooks.stopAnsweringPermissions(agent.id) }
                        tick += 1
                    })) {
                        Text(tr("Responder pedidos de permissão pelo aquário (quem tem o app pode aprovar comandos no seu Mac)"))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    .toggleStyle(.switch).controlSize(.mini)
                    .padding(.leading, 78)
                }
            }
        }
        .opacity(present || connected ? 1 : 0.55)
    }

    private func heading(_ s: String) -> some View {
        Text(s.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary)
            .padding(.bottom, -8)
    }

    /// A part of the card: the slightly lighter water the cards put their sections on.
    private func box<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content()
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(0.07)))
    }

    private func pill(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        let tint = Color(nsColor: WelcomeWindow.tint)
        return Button(action: action) {
            Text(title).font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .foregroundStyle(filled ? Color.black.opacity(0.85) : tint)
                .background(Capsule().fill(filled ? tint : tint.opacity(0.12)))
                .overlay(Capsule().strokeBorder(tint.opacity(filled ? 0 : 0.45)))
        }
        .buttonStyle(.plain)
    }

    private func color(_ id: String) -> Color {
        let c = Self.looks[id]?.color ?? SIMD3(0.5, 0.8, 0.8)
        return Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z))
    }

    /// The fish's pictures, drawn by the GPU off the main thread (the same as the cards' portraits).
    private func drawPortraits() async {
        let looks = Self.looks
        let drawn: [String: CGImage] = await Task.detached(priority: .userInitiated) {
            var out: [String: CGImage] = [:]
            for (id, look) in looks {
                guard let species = FishKinds.all.firstIndex(where: { $0.id == look.kind }) else { continue }
                let job = FishPortraits.portraitJob(species: species, color: look.color, pattern: 0, cut: 0)
                if let img = FishPortraits.portrait(job) { out[id] = img }
            }
            return out
        }.value
        portraits = drawn
    }
}
