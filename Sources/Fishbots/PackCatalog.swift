import AppKit

/// The pack catalog: an index.json (community/index.json in the repository) listing packs with their metadata, cover
/// and files. "Explorar pacotes…" shows it; installing downloads the listed files and goes through the same checked
/// install as a .fishbotspack.
/// Where the index lives: FISHBOTS_CATALOG, or "catalog" in config.json, or the repository's.
enum PackCatalog {
    struct Entry {
        let id: String
        let name: String
        let version: String
        let author: String
        let license: String
        let description: String
        let path: String
        let files: [String]
        let contents: [String: Int]
        let homepage: String?
        let minApp: String?
    }

    static let defaultURL = "https://raw.githubusercontent.com/vitalbh/fishbots/main/community/index.json"

    static var indexURL: URL {
        if let e = Env.value("CATALOG"), e != "off", let u = URL(string: e) { return u }
        if let d = try? Data(contentsOf: Attention.configURL),
           let j = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any],
           let s = j["catalog"] as? String, let u = URL(string: s) { return u }
        return URL(string: defaultURL)!
    }

    /// Only https (and file:, to try a local catalog).
    private static func allowed(_ u: URL) -> Bool { u.scheme == "https" || u.scheme == "file" }

    static func fetch(_ done: @escaping (Result<[Entry], Error>) -> Void) {
        struct Failure: LocalizedError { let errorDescription: String? }
        let url = indexURL
        guard allowed(url) else { done(.failure(Failure(errorDescription: tr("o catálogo precisa ser https")))); return }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        req.setValue("Fishbots", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, _, error in
            let result: Result<[Entry], Error>
            if let error { result = .failure(error) }
            else if let data, let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let packs = j["packs"] as? [[String: Any]] {
                result = .success(packs.compactMap(entry))
            } else { result = .failure(Failure(errorDescription: tr("o catálogo não pôde ser lido"))) }
            DispatchQueue.main.async { done(result) }
        }.resume()
    }

    private static func entry(_ p: [String: Any]) -> Entry? {
        guard let id = p["id"] as? String, let name = p["name"] as? String, let path = p["path"] as? String,
              let files = p["files"] as? [String] else { return nil }
        let lang = L10n.resolved
        return Entry(id: id, name: (p["names"] as? [String: String])?[lang] ?? name, version: p["version"] as? String ?? "",
                     author: p["author"] as? String ?? "", license: p["license"] as? String ?? "",
                     description: (p["descriptions"] as? [String: String])?[lang] ?? p["description"] as? String ?? "",
                     path: path, files: files, contents: p["contents"] as? [String: Int] ?? [:],
                     homepage: p["homepage"] as? String, minApp: p["minApp"] as? String)
    }

    /// A file of a pack, resolved against the index's address (paths are from the repository's root).
    static func url(_ e: Entry, _ file: String) -> URL? {
        URL(string: "../" + e.path + "/" + file, relativeTo: indexURL)?.absoluteURL
    }

    /// What's installed of it: nil (not installed), "link" (a pack being made, linked) or its version.
    static func installed(_ e: Entry) -> String? {
        let dir = Packs.folder.appendingPathComponent(e.id)
        if (try? dir.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { return "link" }
        guard FileManager.default.fileExists(atPath: dir.appendingPathComponent("pack.json").path) else { return nil }
        return Packs.loaded.first { $0.id == e.id }?.version ?? ""
    }

    static func hasUpdate(_ e: Entry) -> Bool {
        guard let v = installed(e), v != "link" else { return false }
        return Packs.older(v, than: e.version)
    }

    /// Downloads the pack's files (only the listed ones, with plain names and pack extensions, at most 5 MB each),
    /// zips them and installs that like a .fishbotspack (the same checks). Returns the pack's id.
    static func install(_ e: Entry, _ done: @escaping (Result<String, Error>) -> Void) {
        struct Failure: LocalizedError { let errorDescription: String? }
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("fishbots-catalog-\(UUID().uuidString)")
        let dir = tmp.appendingPathComponent(e.id)
        let ok = Set(["json", "metal", "md", "txt", "png", "wav", "aif", "aiff", "caf"])
        let files = e.files.filter { !$0.contains("/") && !$0.hasPrefix(".") && ok.contains(($0 as NSString).pathExtension.lowercased()) }
        guard files.contains("pack.json"), (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else {
            done(.failure(Failure(errorDescription: tr("o pacote do catálogo está incompleto")))); return
        }
        let group = DispatchGroup()
        var failed: String?
        for f in files {
            guard let u = url(e, f), allowed(u) else { failed = f; continue }
            group.enter()
            URLSession.shared.dataTask(with: u) { data, response, error in
                defer { group.leave() }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 200
                guard error == nil, status == 200, let data, data.count < 5_000_000 else { failed = f; return }
                try? data.write(to: dir.appendingPathComponent(f))
            }.resume()
        }
        group.notify(queue: .main) {
            defer { try? fm.removeItem(at: tmp) }
            if let failed { done(.failure(Failure(errorDescription: tr("não consegui baixar %@", failed)))); return }
            let zip = tmp.appendingPathComponent("\(e.id).fishbotspack")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            p.arguments = ["-c", "-k", dir.path, zip.path]
            do {
                try p.run(); p.waitUntilExit()
                done(.success(try Packs.install(zip)))
            } catch { done(.failure(error)) }
        }
    }
}

/// The "Explorar pacotes…" window: the catalog's packs with their cover, what they bring and a button to install
/// or update.
final class PackCatalogWindow: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let list = NSStackView()
    private let status = NSTextField(labelWithString: "")
    /// A pack was installed (the app reloads the packs).
    var onInstalled: ((String) -> Void)?

    func show() {
        if let w = window { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); refresh(); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 640), styleMask: [.titled, .closable, .resizable],
                         backing: .buffered, defer: false)
        w.title = tr("Explorar pacotes")
        w.isReleasedWhenClosed = false
        w.delegate = self
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 14
        list.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        let doc = FlippedView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        list.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(list)
        scroll.documentView = doc
        NSLayoutConstraint.activate([
            list.topAnchor.constraint(equalTo: doc.topAnchor), list.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: doc.trailingAnchor), list.bottomAnchor.constraint(equalTo: doc.bottomAnchor),
            doc.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
        ])
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 11)
        status.lineBreakMode = .byTruncatingMiddle
        let root = NSStackView(views: [scroll, status])
        root.orientation = .vertical
        root.spacing = 6
        root.edgeInsets = NSEdgeInsets(top: 0, left: 0, bottom: 10, right: 0)
        w.contentView = root
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        refresh()
    }

    private final class FlippedView: NSView { override var isFlipped: Bool { true } }

    func refresh() {
        status.stringValue = tr("lendo o catálogo…") + "  " + PackCatalog.indexURL.absoluteString
        PackCatalog.fetch { [weak self] r in
            guard let self else { return }
            switch r {
            case .failure(let e): self.status.stringValue = tr("catálogo indisponível: %@", e.localizedDescription)
            case .success(let entries):
                self.status.stringValue = PackCatalog.indexURL.absoluteString
                self.list.arrangedSubviews.forEach { $0.removeFromSuperview() }
                if !entries.isEmpty { self.header(tr("Da comunidade")); entries.forEach(self.row) }
                if entries.isEmpty { self.header(tr("O catálogo está vazio")) }
            }
        }
    }

    private func header(_ t: String) {
        let l = NSTextField(labelWithString: t.uppercased())
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .secondaryLabelColor
        list.addArrangedSubview(l)
    }

    private func row(_ e: PackCatalog.Entry) {
        let cover = NSImageView()
        cover.imageScaling = .scaleProportionallyUpOrDown
        cover.wantsLayer = true
        cover.layer?.cornerRadius = 6
        cover.layer?.masksToBounds = true
        cover.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([cover.widthAnchor.constraint(equalToConstant: 216), cover.heightAnchor.constraint(equalToConstant: 96)])
        if let u = PackCatalog.url(e, "cover.png"), e.files.contains("cover.png") {
            URLSession.shared.dataTask(with: u) { d, _, _ in
                guard let d, let img = NSImage(data: d) else { return }
                DispatchQueue.main.async { cover.image = img }
            }.resume()
        }
        let title = NSTextField(labelWithString: e.name)
        title.font = .systemFont(ofSize: 14, weight: .semibold)
        let by = [e.author.isEmpty ? nil : tr("por %@", e.author), e.version.isEmpty ? nil : "v" + e.version, e.license.isEmpty ? nil : e.license]
        let meta = NSTextField(labelWithString: by.compactMap { $0 }.joined(separator: " · "))
        meta.font = .systemFont(ofSize: 11)
        meta.textColor = .secondaryLabelColor
        let desc = NSTextField(wrappingLabelWithString: e.description)
        desc.font = .systemFont(ofSize: 12)
        desc.preferredMaxLayoutWidth = 340
        let names = ["themes": tr("tema"), "styles": tr("música"), "fish": tr("peixe"), "scenery": tr("cenário"), "fauna": tr("criatura"), "agents": tr("agente"), "presences": tr("presença"), "sounds": tr("som")]
        let brings = ["themes", "fish", "scenery", "fauna", "presences", "styles", "sounds", "agents"].compactMap { k in e.contents[k].map { "\($0) \(names[k]!)" } }
        let what = NSTextField(labelWithString: brings.joined(separator: " · "))
        what.font = .systemFont(ofSize: 11)
        what.textColor = .tertiaryLabelColor
        let button = NSButton(title: "", target: self, action: #selector(act(_:)))
        button.bezelStyle = .rounded
        button.identifier = NSUserInterfaceItemIdentifier(e.id)
        objc_setAssociatedObject(button, &PackCatalogWindow.key, e.id, .OBJC_ASSOCIATION_RETAIN)
        entries[e.id] = e
        style(button, e)
        let text = NSStackView(views: [title, meta, desc, what, button])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 4
        let row = NSStackView(views: [cover, text])
        row.alignment = .top
        row.spacing = 14
        list.addArrangedSubview(row)
    }

    private static var key = 0
    private var entries: [String: PackCatalog.Entry] = [:]

    private func style(_ b: NSButton, _ e: PackCatalog.Entry) {
        b.isEnabled = true
        if let min = e.minApp, Packs.older(Packs.appVersion, than: min) { b.title = tr("Precisa do Fishbots %@", min); b.isEnabled = false; return }
        switch PackCatalog.installed(e) {
        case nil: b.title = tr("Instalar")
        case "link": b.title = tr("Em desenvolvimento (link)"); b.isEnabled = false
        default: if PackCatalog.hasUpdate(e) { b.title = tr("Atualizar para v%@", e.version) } else { b.title = tr("Instalado ✓"); b.isEnabled = false }
        }
    }

    @objc private func act(_ b: NSButton) {
        guard let id = objc_getAssociatedObject(b, &PackCatalogWindow.key) as? String, let e = entries[id] else { return }
        b.isEnabled = false
        b.title = tr("Instalando…")
        PackCatalog.install(e) { [weak self] r in
            guard let self else { return }
            switch r {
            case .success(let id):
                self.onInstalled?(id)
                self.style(b, e)
                self.status.stringValue = tr("pacote instalado: %@", e.name)
            case .failure(let err):
                b.isEnabled = true
                b.title = tr("Instalar")
                self.status.stringValue = tr("pacote não instalado: %@", err.localizedDescription)
            }
        }
    }
}
