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
        var applyLanguage: (String) -> Void
        var plugins: () -> [(name: String, ok: Bool, detail: String)]
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
                Picker(tr("Tema"), selection: prefs.bind({ Themes.current.id }, { Themes.current = Themes.named($0); a.applyTheme() })) {
                    ForEach(Themes.all, id: \.id) { Text($0.displayName).tag($0.id) }
                }
                Toggle(tr("Aurora de fundo"), isOn: prefs.flag("auroraBackground", default: true))
                Picker(tr("Brilho (bloom)"), selection: prefs.bind({ UserDefaults.standard.object(forKey: "bloom") as? Double ?? 1.1 },
                                                               { UserDefaults.standard.set($0, forKey: "bloom") })) {
                    Text(tr("Desligado")).tag(0.0)
                    Text(tr("Suave")).tag(0.7)
                    Text(tr("Normal")).tag(1.1)
                    Text(tr("Forte")).tag(1.6)
                }
                Toggle(tr("Cores da hora (amanhecer, fim de tarde, noite)"), isOn: prefs.flag("hourColors", default: true))
                Toggle(tr("Neve marinha"), isOn: prefs.flag("marineSnow", default: true))
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

// MARK: - window

final class PreferencesWindow {
    private var window: NSWindow?
    private let prefs: Prefs

    init(_ a: Prefs.Actions) { prefs = Prefs(a) }

    func show(tab: Int? = nil) {
        if let tab { prefs.tab = tab }
        if window == nil {
            let host = NSHostingController(rootView: PrefsView(prefs: prefs))
            let w = NSWindow(contentViewController: host)
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
