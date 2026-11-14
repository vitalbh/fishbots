import AppKit
import SwiftUI

/// The bridge between the preferences window and the app: each setting is read and written through closures the app
/// provides (several have side effects: the theme reapplies, "only in the menu bar" changes the Dock…).
final class Prefs: ObservableObject {
    struct Actions {
        var openAtLogin: () -> Bool
        var toggleLogin: () -> Void
        var menuBarOnly: () -> Bool
        var toggleMenuBarOnly: () -> Void
        var floating: () -> Bool
        var toggleFloat: () -> Void
        var soundOn: () -> Bool
        var toggleMute: () -> Void
        /// A global shortcut (nil: back to its default); all paused while a new one is being recorded.
        var setShortcut: (HotkeyAction, Shortcut?) -> Void
        var pauseShortcut: (Bool) -> Void
        var volume: () -> Double
        var setVolume: (Double) -> Void
        var applyTheme: () -> Void
        var openThemePicker: () -> Void
        var applyLanguage: (String) -> Void
        var reloadAgents: () -> Void
        /// The fish take their kind again (after choosing an agent's fish).
        var refreshFish: () -> Void
        var chooseWidgetPlace: (String) -> Void
        var widgetSizeChanged: () -> Void
        /// The assistant was turned on or off, or got another brain: its creature comes or goes.
        var assistantChanged: () -> Void
        var plugins: () -> [(name: String, ok: Bool, detail: String)]
        /// Other devices: their switch is a plain flag, the pairing comes from here.
        var remote: () -> Remote
    }
    let a: Actions
    /// The tab shown.
    @Published var tab = 0
    init(_ a: Actions) { self.a = a }

    /// A binding that refreshes the window after every change.
    func bind<T>(_ get: @escaping () -> T, _ set: @escaping (T) -> Void) -> Binding<T> {
        Binding(get: get, set: { [weak self] v in set(v); self?.objectWillChange.send() })
    }

    /// A Bool stored in UserDefaults under a key.
    func flag(_ key: String, default def: Bool = false) -> Binding<Bool> {
        bind({ UserDefaults.standard.object(forKey: key) as? Bool ?? def }, { UserDefaults.standard.set($0, forKey: key) })
    }

    func refresh() { objectWillChange.send() }
}

struct PrefsView: View {
    @ObservedObject var prefs: Prefs

    var body: some View {
        TabView(selection: $prefs.tab) {
            GeneralTab(prefs: prefs).tabItem { Label(tr("Geral"), systemImage: "gearshape") }.tag(0)
            LookTab(prefs: prefs).tabItem { Label(tr("Aparência"), systemImage: "paintpalette") }.tag(1)
            AttentionTab(prefs: prefs).tabItem { Label(tr("Atenção"), systemImage: "bell.badge") }.tag(2)
            ExtrasTab(prefs: prefs).tabItem { Label(tr("Plugins e pacotes"), systemImage: "puzzlepiece.extension") }.tag(3)
            AssistantTab(prefs: prefs).tabItem { Label(tr("Assistente"), systemImage: "bubble.left.and.text.bubble.right") }.tag(4)
        }
        .frame(width: 560, height: 470)
    }
}

/// Records a global shortcut: click Gravar, press the keys.
struct ShortcutRecorder: View {
    @ObservedObject var prefs: Prefs
    let action: HotkeyAction
    // (SwiftUI.State: the app has its own State, the fish's)
    @SwiftUI.State var recording = false
    @SwiftUI.State var monitor: Any?

    var body: some View {
        HStack {
            Text(action.title)
            Spacer()
            Text(recording ? tr("aperte o atalho…") : action.shortcut.display)
                .font(.system(.body, design: .rounded).weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(recording ? 0.25 : 0.12)))
            Button(recording ? tr("Cancelar") : tr("Gravar")) { recording ? stop() : start() }
            Button(tr("Padrão")) { stop(); prefs.a.setShortcut(action, nil); prefs.refresh() }
                .disabled(action.shortcut == action.standard)
        }
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        prefs.a.pauseShortcut(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            if e.keyCode == 53 { stop(); return nil }                       // Esc: cancel
            guard let s = Shortcut(event: e) else { NSSound.beep(); return nil }
            prefs.a.setShortcut(action, s)
            stop()
            prefs.refresh()
            return nil
        }
    }

    private func stop() {
        guard recording || monitor != nil else { return }
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        if recording { recording = false; prefs.a.pauseShortcut(false) }
    }
}

// MARK: - tabs

private struct GeneralTab: View {
    @ObservedObject var prefs: Prefs
    var body: some View {
        let a = prefs.a
        Form {
            Section(tr("Idioma")) {
                Picker(tr("Idioma"), selection: prefs.bind({ L10n.setting }, { a.applyLanguage($0) })) {
                    Text(tr("Automático (o do Mac)")).tag("auto")
                    Text(verbatim: "Português").tag("pt")
                    Text(verbatim: "English").tag("en")
                }
                Text(tr("A voz que lê e a transcrição seguem o idioma. Os textos do próprio macOS (avisos de permissão) mudam ao reabrir o app."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(tr("App")) {
                Toggle(tr("Abrir no login"), isOn: prefs.bind(a.openAtLogin, { _ in a.toggleLogin() }))
                Toggle(tr("Só na barra de menus (sem ícone no Dock)"), isOn: prefs.bind(a.menuBarOnly, { _ in a.toggleMenuBarOnly() }))
                Toggle(tr("Flutuar sobre as janelas"), isOn: prefs.bind(a.floating, { _ in a.toggleFloat() }))
            }
            Section(tr("Sessões")) {
                Picker(tr("Abrir sessões novas em"), selection: prefs.bind({ UserDefaults.standard.string(forKey: "launcher") ?? "" },
                                                                           { UserDefaults.standard.set($0, forKey: "launcher") })) {
                    Text(tr("Automático")).tag("")
                    Divider()
                    ForEach(Launchers.all.filter(\.available), id: \.id) { Text(verbatim: $0.name).tag($0.id) }
                }
                Text(tr("Onde abre uma sessão que você começa pelo aquário (os ovos, o menu, o assistente). Uma sessão aberta por outra abre ao lado dela, no terminal dela. Automático: Rex, Herdr, iTerm, tmux, nessa ordem, o primeiro que estiver instalado."))
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle(tr("Sessões podem comandar outras (responder, parar, esperar)"), isOn: prefs.flag("sessionControl"))
                Text(tr("Deixa um agente conduzir os outros pelo aquário (fishbots reply, stop, wait). Pedidos de permissão continuam com você."))
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle(tr("Também as sessões abertas fora do aquário"), isOn: prefs.flag("sessionControlOutside", default: true))
                    .disabled(!UserDefaults.standard.bool(forKey: "sessionControl"))
                Text(tr("Uma sessão que o aquário abre recebe uma chave só dela e comanda apenas as que ela mesma abriu. As outras sessões usam a chave do arquivo control.token, a mesma do comando fishbots no seu terminal, que alcança todas. Desligado, essa chave é recusada quando quem pede é uma dessas sessões; seu terminal continua podendo."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            RemotePairingSection(prefs: prefs, remote: a.remote())
            Section(tr("Atalhos")) {
                ForEach(HotkeyAction.allCases, id: \.self) { ShortcutRecorder(prefs: prefs, action: $0) }
                Text(tr("Funcionam em qualquer app, sempre com quem espera por você há mais tempo. Use ao menos uma tecla modificadora (⌃ ⌥ ⇧ ⌘); Esc cancela a gravação. No campo de resposta, Enter envia."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(tr("Som")) {
                Toggle(tr("Som ligado"), isOn: prefs.bind(a.soundOn, { _ in a.toggleMute() }))
                HStack {
                    Image(systemName: "speaker.fill").foregroundStyle(.secondary)
                    Slider(value: prefs.bind(a.volume, a.setVolume), in: 0...1)
                    Image(systemName: "speaker.wave.3.fill").foregroundStyle(.secondary)
                }
                Toggle(tr("Música ambiente (tocar o tempo todo)"), isOn: prefs.flag("ambientMusic"))
                Toggle(tr("Uma nota a cada ferramenta usada"), isOn: prefs.flag("toolNotes"))
                Toggle(tr("Ler as perguntas em voz alta"), isOn: prefs.flag("readQuestions"))
                Toggle(tr("Peixe da música que está tocando (Spotify, Música)"), isOn: prefs.bind({ NowPlaying.enabled }, { NowPlaying.enabled = $0 }))
                Text(tr("Mostra a faixa e o artista, brilha quando a música muda e pausa a música ambiente enquanto toca."))
                    .font(.footnote).foregroundStyle(.secondary)
                Toggle(tr("Visualizadores dançam com essa música"), isOn: prefs.bind({ SongEars.enabled }, { SongEars.enabled = $0 }))
                    .disabled(!NowPlaying.enabled)
                Text(tr("Escuta só o som do Spotify ou do Música, enquanto toca, para as notas e acordes virarem luz no aquário. Nada é gravado nem sai do Mac. Ao ligar, o macOS pede a permissão de Gravação de Áudio do Sistema."))
                    .font(.footnote).foregroundStyle(.secondary)
                switch SongEars.status {
                case .silent:
                    Text(tr("Não chega som: confira em Ajustes do Sistema → Privacidade e Segurança → Gravação de Tela e Áudio do Sistema."))
                        .font(.footnote).foregroundStyle(.orange)
                case .failed(let why):
                    Text(String(format: tr("Não consegui escutar o player: %@"), why))
                        .font(.footnote).foregroundStyle(.orange)
                default: EmptyView()
                }
            }
            Section(tr("Agentes")) {
                // built in (Swift) and through /agent/<id> (AgentManifests.swift)
                LabeledContent(tr("Integrados"), value: AgentManifests.builtIn.map(\.name).joined(separator: ", "))
                let others = AgentManifests.viaRoute
                LabeledContent(tr("Por /agent/<id>"),
                               value: others.isEmpty ? tr("nenhum ainda")
                                   : others.map { $0.name + ($0.manifest ? "" : tr(" (sem manifesto)")) }.joined(separator: ", "))
                ForEach(AgentManifests.problems, id: \.self) { Text(tr("⚠︎ ") + $0).font(.footnote).foregroundStyle(.orange) }
                DisclosureGroup(tr("Peixe de cada agente")) {
                    let agents = AgentManifests.builtIn.map { ($0.id, $0.name) } + others.map { ($0.id, $0.name) }
                    ForEach(agents, id: \.0) { agent in
                        Picker(agent.1, selection: prefs.bind({ FishKinds.agentKind(agent.0) ?? "" },
                                                              { FishKinds.setAgentKind($0.isEmpty ? nil : $0, for: agent.0); a.refreshFish() })) {
                            Text(tr("Automático (pelo terminal)")).tag("")
                            Divider()
                            ForEach(FishKinds.all.filter { $0.id != "betta" }, id: \.id) { k in
                                Text(tr(k.name) + (k.pack != nil ? tr(" (pacote)") : "")).tag(k.id)
                            }
                        }
                    }
                    Text(tr("Vale para todos os peixes do agente, menos nos projetos onde você escolheu o peixe no menu dele. Um peixe escolhido aqui não é vestido pelo tema."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                DisclosureGroup(tr("Linha de comando de cada agente")) {
                    ForEach(AgentCLIRow.agents, id: \.id) { AgentCLIRow(prefs: prefs, agent: $0.id, name: $0.name, usual: $0.usual) }
                    Text(tr("Como o aquário chama o agente quando é ele quem abre: uma nova sessão num terminal e o assistente. Um alias do seu shell não chega até aí; escreva aqui o que ele fazia (o binário, parâmetros, variáveis como CLAUDE_CONFIG_DIR=~/.claude-trabalho). Em branco: o comando de sempre."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                HStack {
                    Button(tr("Abrir pasta de agentes")) { AgentManifests.openFolder() }
                    Button(tr("Recarregar")) { prefs.a.reloadAgents(); prefs.refresh() }
                }
                Text(tr("Outros agentes entram mandando eventos para /agent/<id>; um manifesto aqui dá nome, peixe e timbre. Depois de mudar um, Recarregar (ou POST /agents/reload). Veja o README."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(tr("Foco")) {
                Toggle(tr("Modo foco (só o que pede atenção)"), isOn: prefs.bind({ Attention.focus }, { Attention.focus = $0 }))
            }
        }
        .formStyle(.grouped)
    }
}

private struct LookTab: View {
    @ObservedObject var prefs: Prefs
    var body: some View {
        let a = prefs.a
        Form {
            Section(tr("Cena")) {
                // the theme window shows each one with its picture and what it brings (a list of names didn't)
                LabeledContent(tr("Tema")) {
                    HStack {
                        Text(Themes.current.displayName).foregroundStyle(.secondary)
                        Button(tr("Escolher tema…")) { a.openThemePicker() }
                    }
                }
                Toggle(tr("Aurora de fundo"), isOn: prefs.flag("auroraBackground", default: true))
                Toggle(tr("Vestir presenças e peixes com o tema"), isOn: prefs.flag("dressByTheme", default: true))
                    .help(tr("O tema pode desenhar as presenças dos plugins e os peixes do jeito dele (a garrafa vira lanterna no lago japonês). O peixe que você escolheu à mão fica como está."))
                Picker(tr("Brilho (bloom)"), selection: prefs.bind({ UserDefaults.standard.object(forKey: "bloom") as? Double ?? 1.1 },
                                                               { UserDefaults.standard.set($0, forKey: "bloom") })) {
                    Text(tr("Desligado")).tag(0.0)
                    Text(tr("Suave")).tag(0.7)
                    Text(tr("Normal")).tag(1.1)
                    Text(tr("Forte")).tag(1.6)
                }
                Toggle(tr("Cores da hora (amanhecer, fim de tarde, noite)"), isOn: prefs.flag("hourColors", default: true))
                Toggle(tr("Cores da capa do álbum na luz da água e na aurora"), isOn: prefs.flag("albumColors", default: true))
                    .help(tr("Enquanto o Spotify ou o Música tocam, as duas cores mais marcantes da capa tingem os raios de luz, as cáusticas e a aurora."))
                Toggle(tr("Neve marinha"), isOn: prefs.flag("marineSnow", default: true))
                Toggle(tr("Poeira dourada nos raios de sol"), isOn: prefs.flag("goldenDust", default: true))
            }
            Section(tr("Widget (W)")) {
                Picker(tr("Onde fica o widget"), selection: prefs.bind({ WindowModes.place }, { a.chooseWidgetPlace($0) })) {
                    ForEach(NSScreen.screens, id: \.self) { s in
                        Text(s.safeAreaInsets.top > 0 ? tr("No notch de %@", s.localizedName) : tr("No topo de %@", s.localizedName))
                            .tag("screen:\(WindowModes.number(s))")
                    }
                    Text(tr("Janelinha no canto")).tag("corner")
                }
                Picker(tr("Abre"), selection: prefs.bind({ WindowModes.opensOnClick }, { WindowModes.opensOnClick = $0 })) {
                    Text(tr("Ao passar o mouse")).tag(false)
                    Text(tr("Com um clique")).tag(true)
                }
                .disabled(WindowModes.place == "corner")
                Toggle(tr("Animações no notch"), isOn: prefs.bind({ WindowModes.animated }, { WindowModes.animated = $0 }))
                    .disabled(WindowModes.place == "corner")
                Picker(tr("Tamanho aberto"), selection: prefs.bind({ WindowModes.size }, { WindowModes.size = $0; a.widgetSizeChanged() })) {
                    ForEach(WindowModes.sizes, id: \.id) { Text(tr($0.name)).tag($0.id) }
                }
                .disabled(WindowModes.place == "corner")
                Text(tr("No notch, clicar no nome de quem espera leva ao terminal dele. Sem animações, os peixinhos ficam parados (o padrão segue o Reduzir movimento do macOS)."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(tr("Visualizador")) {
                Picker(tr("Visualizador"), selection: prefs.bind({ UserDefaults.standard.string(forKey: "visual") ?? "auto" },
                                                             { UserDefaults.standard.set($0, forKey: "visual") })) {
                    Text(tr("Automático (pelo estilo e pelo tema)")).tag("auto")
                    Text(tr("Aleatório (troca a cada peça)")).tag("random")
                    Text(tr("Só a aurora / nenhum")).tag("off")
                    Divider()
                    ForEach(Visualizers.all.map { ($0.id, $0.title) }, id: \.0) { Text($0.1).tag($0.0) }
                }
            }
            Section(tr("Rótulos")) {
                Picker(tr("Nos peixes"), selection: prefs.bind({ UserDefaults.standard.string(forKey: "labels") ?? "minimal" },
                                                          { UserDefaults.standard.set($0, forKey: "labels") })) {
                    Text(tr("Mínimo (o nome, e a segunda linha quando importa)")).tag("minimal")
                    Text(tr("Completo")).tag("full")
                    Text(tr("Nenhum")).tag("none")
                }
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
    }
}

/// Attention rules ("source:state" → level): the defaults, yours (stored in the app) and config.json's.
private struct AttentionTab: View {
    @ObservedObject var prefs: Prefs
    @SwiftUI.State private var newSource = ""
    @SwiftUI.State private var newState = "*"
    @SwiftUI.State private var newLevel = Level.urgent

    private static let states = ["*"] + State.allCases.map(\.rawValue)
    private static let stateNames = ["*": "qualquer estado", "born": "chegou", "busy": "trabalhando", "idle": "parado",
                                     "waiting": "esperando você", "ok": "ok", "alert": "alerta", "error": "erro", "done": "terminou"]
    private static let levelNames: [Level: String] = [.ambient: "ambiente (só a cor)", .attention: "atenção (som)", .urgent: "urgente (notificação)"]

    private var mine: [(key: String, level: Level)] {
        Attention.fromMenu.map { ($0.key, $0.value) }.sorted { $0.key < $1.key }
    }

    var body: some View {
        Form {
            Section {
                Toggle(tr("Notificar quando esperarem por você"), isOn: prefs.bind({ Attention.level("*", .waiting) == .urgent },
                                                                               { Attention.setLevel("*:waiting", $0 ? .urgent : .attention) }))
                    .disabled(Attention.fromFile["*:waiting"] != nil)
                Toggle(tr("Seguir o Foco do macOS (Não Perturbe, Trabalho…)"), isOn: prefs.bind({ FocusFollow.enabled }, { FocusFollow.enabled = $0 }))
                Toggle(tr("Notificar erros"), isOn: prefs.bind({ Attention.level("*", .error) == .urgent },
                                                           { Attention.setLevel("*:error", $0 ? .urgent : .attention) }))
                    .disabled(Attention.fromFile["*:error"] != nil)
            } footer: {
                if Attention.fromFile["*:waiting"] != nil || Attention.fromFile["*:error"] != nil {
                    Text(tr("Desativado onde o config.json já define (ele vale sobre as regras daqui).")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            Section {
                ForEach(mine, id: \.key) { rule in
                    HStack {
                        Text(describe(rule.key)).frame(maxWidth: .infinity, alignment: .leading)
                        Picker(tr(""), selection: prefs.bind({ rule.level }, { Attention.setLevel(rule.key, $0) })) {
                            ForEach([Level.ambient, .attention, .urgent], id: \.self) { Text(tr(Self.levelNames[$0]!)).tag($0) }
                        }
                        .labelsHidden().frame(width: 190)
                        Button { Attention.removeRule(rule.key); prefs.refresh() } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless)
                    }
                }
                HStack {
                    TextField("fonte", text: $newSource, prompt: Text(tr("fonte (ex.: github)"))).labelsHidden().frame(minWidth: 120)
                    Picker(tr(""), selection: $newState) {
                        ForEach(Self.states, id: \.self) { Text(tr(Self.stateNames[$0] ?? $0)).tag($0) }
                    }
                    .labelsHidden().frame(width: 140)
                    Picker(tr(""), selection: $newLevel) {
                        ForEach([Level.ambient, .attention, .urgent], id: \.self) { Text(tr(Self.levelNames[$0]!)).tag($0) }
                    }
                    .labelsHidden().frame(width: 170)
                    Button {
                        let src = newSource.trimmingCharacters(in: .whitespaces)
                        Attention.setLevel((src.isEmpty ? "*" : src) + ":" + newState, newLevel)
                        newSource = ""
                        prefs.refresh()
                    } label: { Image(systemName: "plus.circle.fill") }
                    .buttonStyle(.borderless)
                }
            } header: {
                Text(tr("Regras"))
            } footer: {
                Text(tr("Quanto cada fonte e estado pode chamar você. As regras daqui valem sobre as padrão; as do config.json valem sobre todas."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(tr("Padrão e config.json")) {
                ForEach(Attention.defaults.sorted { $0.key < $1.key }, id: \.key) { r in
                    HStack { Text(describe(r.key)); Spacer(); Text(tr(Self.levelNames[r.value]!)).foregroundStyle(.secondary) }
                }
                ForEach(Attention.fromFile.sorted { $0.key < $1.key }, id: \.key) { r in
                    HStack { Text(describe(r.key) + "  (config.json)"); Spacer(); Text(tr(Self.levelNames[r.value]!)).foregroundStyle(.secondary) }
                }
                Button(tr("Abrir o config.json… (webhooks, ações no menu do peixe)")) { Attention.openConfig() }
            }
        }
        .formStyle(.grouped)
    }

    private func describe(_ key: String) -> String {
        let p = key.split(separator: ":", maxSplits: 1).map(String.init)
        let src = p.first.map { $0 == "*" ? tr("qualquer fonte") : $0 } ?? key
        let st = tr(p.count > 1 ? (Self.stateNames[p[1]] ?? p[1]) : "qualquer estado")
        return "\(src) · \(st)"
    }
}

private struct ExtrasTab: View {
    @ObservedObject var prefs: Prefs
    var body: some View {
        let plugins = prefs.a.plugins()
        Form {
            Section {
                if plugins.isEmpty { Text(tr("Nenhum plugin instalado.")).foregroundStyle(.secondary) }
                ForEach(plugins, id: \.name) { p in
                    HStack {
                        Image(systemName: p.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(p.ok ? .green : .orange)
                        Text(p.name)
                        Spacer()
                        Text(p.detail).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                        Button(tr("Ver log")) { Plugins.openLog(p.name) }.controlSize(.small)
                    }
                }
                Button(tr("Abrir a pasta de plugins")) { Plugins.openFolder() }
            } header: {
                Text(tr("Plugins"))
            } footer: {
                Text(tr("Scripts que mandam peixes, eventos e medidores (veja plugins/examples no repositório)."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(tr("Pacotes")) {
                if Packs.loaded.isEmpty { Text(tr("Nenhum pacote.")).foregroundStyle(.secondary) }
                ForEach(Packs.loaded, id: \.id) { p in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tr("📦 ") + p.name)
                        if !p.contents.isEmpty { Text(p.contents.joined(separator: ", ")).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                ForEach(Packs.problems, id: \.self) { Text(tr("⚠︎ ") + $0).font(.footnote).foregroundStyle(.orange) }
                Button(tr("Abrir a pasta de pacotes")) { NSWorkspace.shared.open(Packs.folder) }
                Text(tr("Pacotes novos entram ao reabrir o app.")).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

/// One agent's command line (AgentCLIs): the binary, extra parameters and variables.
private struct AgentCLIRow: View {
    static let agents: [(id: String, name: String, usual: String)] = [("claude-code", "Claude Code", "claude"), ("codex", "Codex", "codex")]
    @ObservedObject var prefs: Prefs
    let agent: String
    let name: String
    let usual: String

    private func field(_ title: String, _ hint: String, _ path: WritableKeyPath<AgentCLI, String>) -> some View {
        TextField(title, text: prefs.bind({ AgentCLIs.settings(agent)[keyPath: path] },
                                          { var c = AgentCLIs.settings(agent); c[keyPath: path] = $0; AgentCLIs.set(agent, c) }),
                  prompt: Text(hint))
            .font(.system(.body, design: .monospaced))
    }

    var body: some View {
        Text(name).font(.headline)
        field(tr("Binário"), usual, \.binary)
        field(tr("Parâmetros"), "", \.arguments)
        field(tr("Variáveis"), "NOME=valor", \.environment)
    }
}

private struct AssistantTab: View {
    @ObservedObject var prefs: Prefs
    @SwiftUI.State var newRule = ""       // (`State` alone is the fish's)

    /// A rule written by hand: a tool's name as it is (one capitalized word, or a connector's "mcp__…"), anything
    /// else a program or the start of a command.
    private func addRule() {
        let words = newRule.split(separator: " ").map(String.init)
        guard let first = words.first else { return }
        let tool = words.count == 1 && (first.hasPrefix("mcp__") || first.range(of: "^[A-Z][A-Za-z]+$", options: .regularExpression) != nil)
        let rule = tool ? first : "Bash:" + words.prefix(2).joined(separator: " ")
        if !Assistant.allowed.contains(rule) { Assistant.allowed.append(rule) }
        newRule = ""
        prefs.refresh()
    }

    var body: some View {
        let a = prefs.a
        let brain = Assistant.brainID
        Form {
            Section {
                Toggle(tr("Um assistente morando no aquário"), isOn: prefs.bind({ Assistant.on }, { Assistant.on = $0; a.assistantChanged() }))
                Text(tr("Uma moreia na toca, sempre ali. Clique nela (ou use o atalho, em Geral → Atalhos) e pergunte: quem espera por você, o que aconteceu hoje. Ela também responde, para e abre sessões quando você pede. Dorme entre as conversas: parada não gasta nada."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(tr("Quem pensa")) {
                Picker(tr("Agente"), selection: prefs.bind({ Assistant.brainID }, { Assistant.brainID = $0; a.assistantChanged() })) {
                    ForEach(Brains.all.map { (id: $0.id, name: $0.name) }, id: \.id) { Text($0.name).tag($0.id) }
                }
                if brain == "command" {
                    TextField(tr("Comando"), text: prefs.bind({ CommandBrain.command }, { CommandBrain.command = $0; a.assistantChanged() }),
                              prompt: Text(tr("recebe a pergunta na entrada, escreve a resposta na saída")))
                        .font(.system(.body, design: .monospaced))
                } else {
                    TextField(tr("Modelo"), text: prefs.bind({ Assistant.model(brain) }, { Assistant.setModel(brain, $0) }),
                              prompt: Text(tr("o padrão do agente")))
                }
                Text(tr("O aquário não tem modelo dentro: quem pensa é o agente que você já usa, rodado em segundo plano, na sua conta e com os conectores que ele já tem (agenda, e-mail…). O binário, os parâmetros e as variáveis dele ficam em Geral → Agentes."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(tr("Voz")) {
                Toggle(tr("Ler as respostas em voz alta"), isOn: prefs.bind({ Assistant.speaks }, { Assistant.speaks = $0 }))
                Text(tr("O que você pergunta falando é sempre respondido em voz alta."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(tr("O que ele faz sem perguntar")) {
                LabeledContent(tr("Sempre"), value: tr("olhar o aquário e escrever as próprias notas"))
                ForEach(Assistant.allowed, id: \.self) { rule in
                    HStack {
                        Text((rule.hasPrefix("Bash:") ? "$ " : "") + Assistant.ruleName(rule))
                            .font(.system(.body, design: .monospaced))
                        Spacer()
                        Button(tr("Remover")) { Assistant.allowed.removeAll { $0 == rule }; prefs.refresh() }.controlSize(.small)
                    }
                }
                HStack {
                    TextField(tr("Permitir sempre"), text: $newRule, prompt: Text(tr("um programa (rex), um comando (git status) ou uma ferramenta (WebFetch)")))
                        .font(.system(.body, design: .monospaced))
                        .onSubmit(addRule)
                    Button(tr("Adicionar"), action: addRule).disabled(newRule.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text(tr("O resto ele pede no card (Permitir, Sempre ou Negar); o que você marcar como Sempre aparece aqui. As permissões que o agente já tem nas configurações dele continuam valendo."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section(tr("Memória")) {
                HStack {
                    Button(tr("Abrir as notas")) {
                        DispatchQueue.global().async {
                            Assistant.prepareFolder()
                            DispatchQueue.main.async { NSWorkspace.shared.open(Assistant.folder.appendingPathComponent("notes.md")) }
                        }
                    }
                    Button(tr("Abrir a pasta dele")) {
                        DispatchQueue.global().async {
                            Assistant.prepareFolder()
                            DispatchQueue.main.async { NSWorkspace.shared.open(Assistant.folder) }
                        }
                    }
                }
                Text(tr("Na pasta ficam as instruções dele (CLAUDE.md, AGENTS.md), as notas que ele lê e escreve e as skills do aquário. A conversa recomeça a cada dia; as notas ficam."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - window

final class PreferencesWindow {
    private var window: NSWindow?
    private let prefs: Prefs

    init(_ a: Prefs.Actions) { prefs = Prefs(a) }
    /// Something changed outside the window (a theme chosen in the themes window): show it.
    func refresh() { prefs.refresh() }

    func show(tab: Int? = nil) {
        if let tab { prefs.tab = tab }
        if window == nil {
            let host = NSHostingController(rootView: PrefsView(prefs: prefs))
            let w = EscClosingWindow(contentViewController: host)
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            // size it before placing it: otherwise SwiftUI grows it upward after centering, and the title bar
            // ends up under the menu bar (where it can't be dragged)
            w.setContentSize(host.view.fittingSize)
            w.center()
            w.setFrameAutosaveName("Preferences")
            window = w
        }
        guard let w = window else { return }
        w.title = tr("Preferências do Fishbots")
        prefs.refresh()
        // always fully on a screen (a saved position may be on a display that's gone)
        if let screen = w.screen ?? NSScreen.main {
            let v = screen.visibleFrame
            var f = w.frame
            f.origin.x = min(max(f.origin.x, v.minX), v.maxX - f.width)
            f.origin.y = min(max(f.origin.y, v.minY), v.maxY - f.height)
            if f != w.frame { w.setFrame(f, display: false) }
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }
}
