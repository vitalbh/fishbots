import SwiftUI
import UIKit

/// Fishbots on the iPhone: the Mac's aquarium, seen from here (Remote.swift on the Mac). The sessions run on the
/// Mac; this app watches them, answers their permission requests and replies to them.
@main
struct FishbotsApp: App {
    @StateObject private var link = MacLink()
    @Environment(\.scenePhase) private var phase

    var body: some SwiftUI.Scene {
        WindowGroup {
            Aquarium(link: link)
                .onOpenURL { url in
                    #if DEBUG
                    if url.host == "test" { NotificationCenter.default.post(name: .fishbotsTest, object: url); return }
                    #endif
                    link.pair(url)
                }
                .onChange(of: phase) { _, p in if p == .active { link.resume() } else if p == .background { link.pause() } }
                .onAppear { link.resume() }
                .preferredColorScheme(.dark)
        }
    }
}

private struct Selected: Identifiable { let id: String }

struct Aquarium: View {
    @ObservedObject var link: MacLink
    @SwiftUI.State private var selected: Selected?
    @AppStorage("labels") private var showLabels = true

    var body: some View {
        ZStack {
            AquariumView(mirror: link.mirror, showLabels: showLabels) { selected = Selected(id: $0) }
                .ignoresSafeArea()
            VStack {
                if link.pairing != nil { StatusPill(link: link, showLabels: $showLabels) }
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
        #if DEBUG
        // Debug builds only: fishbots://test?do=allow|deny|answer:<text>|open:<fish id>|reply:<text>|close|theme:<id>|themeMac|labels:on|off, so a script
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
            else if d == "close" { selected = nil }
            else if d.hasPrefix("theme:") { link.theme = String(d.dropFirst(6)) }
            else if d == "themeMac" { link.useThemeOnMac() }
            else if d.hasPrefix("labels:") { showLabels = d.hasSuffix("on") }
        }
        #endif
        .onChange(of: link.permissions.map(\.id)) { old, new in
            if new.contains(where: { !old.contains($0) }) { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
        }
    }
}

/// Which Mac, and whether it's reachable; its menu pairs again or forgets it.
private struct StatusPill: View {
    @ObservedObject var link: MacLink
    @Binding var showLabels: Bool

    var body: some View {
        Menu {
            Picker(tr("Tema"), selection: $link.theme) {
                Text(tr("Igual ao Mac")).tag("")
                ForEach(Themes.all, id: \.id) { Text($0.displayName).tag($0.id) }
            }
            .pickerStyle(.menu)
            if !link.theme.isEmpty {
                Button(tr("Usar este tema no Mac também")) { link.useThemeOnMac() }
            }
            Toggle(tr("Nomes dos peixes"), isOn: $showLabels)
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
