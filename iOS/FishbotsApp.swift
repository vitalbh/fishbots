import SwiftUI
import UIKit

/// Fishbots on the iPhone: the Mac's aquarium, seen from here (Remote.swift on the Mac). The sessions run on the
/// Mac; this app watches them, answers their permission requests and replies to them.
@main
struct FishbotsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @ObservedObject private var link = MacLink.shared

    var body: some SwiftUI.Scene {
        WindowGroup {
            Aquarium(link: link)
                .onOpenURL { url in
                    #if DEBUG
                    if url.host == "test" { NotificationCenter.default.post(name: .fishbotsTest, object: url); return }
                    #endif
                    link.pair(url)
                }
                .onAppear { link.resume() }
                .preferredColorScheme(.dark)
        }
    }
}

private struct Selected: Identifiable { let id: String }
/// A presence whose card is open (with the rest of its source's).
private struct Shown: Identifiable { let source: String; let presence: String; var id: String { source + ":" + presence } }

struct Aquarium: View {
    @ObservedObject var link: MacLink
    @SwiftUI.State private var selected: Selected?
    @AppStorage("labels") private var showLabels = true
    @SwiftUI.State private var newSession = false
    @SwiftUI.State private var talking = false
    @SwiftUI.State private var shown: Shown?

    var body: some View {
        ZStack {
            AquariumView(mirror: link.mirror, showLabels: showLabels) { touch in
                switch touch {
                case .fish(let id): selected = Selected(id: id)
                case .eggs: if link.status == .connected { newSession = true }
                case .chest: link.recent(hours: 3)
                case .assistant: talking = true
                case .knock(let x): link.sound.knock(x: x)
                case .presence(let source, let id): shown = Shown(source: source, presence: id)
                }
            }
                .ignoresSafeArea()
            VStack {
                if link.pairing != nil { StatusPill(link: link, showLabels: $showLabels, newSession: $newSession, talking: $talking) }
                if !link.away.isEmpty && link.pairing != nil { AwayCard(link: link) { selected = Selected(id: $0) } }
                Spacer()
                if let n = link.notice {
                    Text(n).font(.footnote).padding(10).background(.ultraThinMaterial, in: Capsule())
                        .onTapGesture { link.notice = nil }
                        .task(id: n) { try? await Task.sleep(for: .seconds(4)); if link.notice == n { link.notice = nil } }
                }
                if let p = link.permissions.first { PermissionCard(link: link, p: p).id(p.id) }
            }
            .padding(.bottom, 8)
            if link.pairing == nil { PairingView(link: link) }
        }
        .sheet(item: $selected) { s in FishCard(link: link, id: s.id).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $newSession) { NewSessionSheet(link: link) }
        .sheet(item: $shown) { s in SourceSheet(link: link, source: s.source, first: s.presence).presentationDetents([.medium, .large]) }
        .sheet(isPresented: $talking) {
            AssistantSheet(link: link) { id in talking = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { selected = Selected(id: id) } }
                .presentationDetents([.medium, .large])
        }
        #if DEBUG
        // Debug builds only: fishbots://test?do=allow|deny|answer:<text>|open:<fish id>|reply:<text>|close|theme:<id>|themeMac|labels:on|off|away:<hours>|new|assistant, so a script
        // can press what a finger would (the simulator can't be tapped from the terminal)
        .onReceive(NotificationCenter.default.publisher(for: .fishbotsTest)) { n in
            guard let url = n.object as? URL, let d = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "do" })?.value else { return }
            let p = link.permissions.first
            if d == "allow" || d == "deny", let p { link.decide(p, decision: d) }
            else if d.hasPrefix("answer:"), let p { link.decide(p, answer: String(d.dropFirst(7))) }
            else if d.hasPrefix("open:") { selected = Selected(id: String(d.dropFirst(5))) }
            else if d.hasPrefix("reply:"), let id = selected?.id, let f = link.fish[id] {
                link.reply(source: f["source"] as? String ?? "", entity: f["entity"] as? String ?? "", text: String(d.dropFirst(6))) { e in link.notice = e ?? "sent" }
            }
            else if d == "close" { selected = nil; newSession = false; shown = nil; talking = false }
            else if d == "new" { newSession = true }
            else if d == "assistant" { talking = true }
            else if d.hasPrefix("theme:") { link.theme = String(d.dropFirst(6)) }
            else if d == "themeMac" { link.useThemeOnMac() }
            else if d.hasPrefix("labels:") { showLabels = d.hasSuffix("on") }
            else if d.hasPrefix("away:") {
                link.pause()
                UserDefaults.standard.set(Date().addingTimeInterval(-(Double(d.dropFirst(5)) ?? 1) * 3600), forKey: "lastSeen")
                link.resume()
            }
        }
        #endif
        .onChange(of: link.openFish) { _, f in
            if let f { selected = Selected(id: f); link.openFish = nil }
        }
        .onChange(of: link.permissions.map(\.id)) { old, new in
            if new.contains(where: { !old.contains($0) }) { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        }
    }
}

/// Which Mac, and whether it's reachable; its menu pairs again or forgets it.
private struct StatusPill: View {
    @ObservedObject var link: MacLink
    @Binding var showLabels: Bool
    @Binding var newSession: Bool
    @Binding var talking: Bool
    @AppStorage("soundOn") private var soundOn = true
    /// Music.swift reads this key itself (the Mac's own).
    @AppStorage("ambientMusic") private var ambientMusic = false

    var body: some View {
        Menu {
            Button { newSession = true } label: { Label(tr("Nova sessão…"), systemImage: "plus.bubble") }
                .disabled(link.status != .connected)
            if link.assistant["on"] as? Bool == true {
                Button { talking = true } label: { Label(tr("Falar com o assistente"), systemImage: "bubble.left.and.text.bubble.right") }
            }
            Divider()
            Picker(tr("Tema"), selection: $link.theme) {
                Text(tr("Igual ao Mac")).tag("")
                ForEach(Themes.all, id: \.id) { Text($0.displayName).tag($0.id) }
            }
            .pickerStyle(.menu)
            if !link.theme.isEmpty {
                Button(tr("Usar este tema no Mac também")) { link.useThemeOnMac() }
            }
            Toggle(tr("Nomes dos peixes"), isOn: $showLabels)
            Toggle(tr("Som"), isOn: Binding(get: { soundOn }, set: { soundOn = $0; link.sound.setOn($0) }))
            Toggle(tr("Música ambiente"), isOn: $ambientMusic)
            Divider()
            Button(tr("Esquecer este Mac"), role: .destructive) { link.forget() }
        } label: {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(link.pairing?.name ?? "").font(.footnote.weight(.medium))
                if case .failed(let why) = link.status { Text("· " + why).font(.footnote).foregroundStyle(.secondary) }
                if link.status == .connecting { Text("· " + tr("conectando…")).font(.footnote).foregroundStyle(.secondary) }
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .foregroundStyle(.primary)
    }

    private var color: Color {
        switch link.status {
        case .connected: .green
        case .connecting: .yellow
        case .failed: .red
        case .unpaired: .gray
        }
    }
}

#if DEBUG
extension Notification.Name { static let fishbotsTest = Notification.Name("fishbotsTest") }
#endif
