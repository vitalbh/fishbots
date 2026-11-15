import AppKit
import CoreImage
import SwiftUI

/// Preferences → General → Other devices: the switch for Remote.swift, and the QR code a phone scans to pair.
struct RemotePairingSection: View {
    @ObservedObject var prefs: Prefs
    let remote: Remote
    let push: Push
    @SwiftUI.State private var keyError: String?
    /// Looked up when the section shows (Remote.refreshTailscale): "" while unknown.
    @SwiftUI.State var tailscale: String? = nil

    var body: some View {
        Section(tr("Outros aparelhos")) {
            let _ = tailscale   // the QR below carries the name: redraw once it's found
            Toggle(tr("Deixar o iPhone ver e responder o aquário"), isOn: prefs.flag("remoteAccess"))
            Text(tr("O app do iPhone vê os peixes, responde pedidos de permissão e manda respostas às sessões, que continuam rodando neste Mac. A conexão é cifrada com a chave do código abaixo: só entra quem leu o código. Funciona na mesma rede, ou de fora pelo Tailscale."))
                .font(.footnote).foregroundStyle(.secondary)
            if Remote.enabled {
                HStack(alignment: .top, spacing: 16) {
                    if let qr = Self.qr(remote.pairingURL) {
                        Image(nsImage: qr).interpolation(.none).resizable().frame(width: 160, height: 160)
                            .padding(6).background(Color.white).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(tr("Abra o Fishbots no iPhone e leia este código."))
                        Text(String(format: tr("Porta %d · %@"), Int(remote.port), Remote.addresses().joined(separator: ", ")))
                            .font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                        if Remote.tailscaleAddress() != nil {
                            Label(String(format: tr("Tailscale: %@. Funciona fora de casa."), tailscale ?? Remote.tailscaleAddress() ?? ""),
                                  systemImage: "checkmark.circle.fill")
                                .font(.footnote).foregroundStyle(.green).textSelection(.enabled)
                        } else {
                            Label(tr("Tailscale não encontrado neste Mac: só funciona na mesma rede."), systemImage: "wifi")
                                .font(.footnote).foregroundStyle(.secondary)
                            Text(tr("Para usar de fora, instale o app Tailscale no Mac e no iPhone, com a mesma conta. O Tailscale embutido em outro app (como o do Rex) não serve: ele não cria um endereço no Mac."))
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
                .task { tailscale = await remote.refreshTailscale() }
                devicesList
            }
        }
        if Remote.enabled { notifications }
    }

    /// The paired devices, each with a key of its own (RemoteDevices): revoking one leaves the others paired.
    @ViewBuilder private var devicesList: some View {
        let paired = remote.devices.paired
        if paired.isEmpty {
            Text(tr("Nenhum aparelho pareado ainda. Cada aparelho que lê o código ganha uma chave só dele.")).font(.footnote).foregroundStyle(.secondary)
        } else {
            ForEach(paired, id: \.id) { d in
                HStack {
                    Image(systemName: d.name.lowercased().contains("ipad") ? "ipad" : "iphone").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(d.name.isEmpty ? tr("aparelho") : d.name)
                        Text(d.seen.map { String(format: tr("visto %@"), RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: Date())) } ?? tr("ainda não visto"))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(tr("Revogar")) { remote.revoke(d.id); prefs.refresh() }
                }
            }
            HStack {
                Text(tr("Revogar tira a chave do aparelho: ele não conecta mais, e os outros seguem pareados.")).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button(tr("Esquecer todos")) { remote.forgetDevices(); prefs.refresh() }
            }
        }
    }

    /// Push.swift: notifications on or off, through iCloud by default, or with a developer account's own APNs key.
    private var notifications: some View {
        Section(tr("Notificações no iPhone")) {
            Toggle(tr("Avisar no iPhone quando uma sessão precisa de você"),
                   isOn: prefs.bind({ Push.enabled }, { UserDefaults.standard.set($0, forKey: "pushEnabled") }))
            Text(tr("Quando uma sessão pede permissão, para esperando você ou dá erro, e o app do iPhone não está aberto. Vai cifrado pelo seu iCloud: nem a Apple lê o que a sessão disse. O Mac e o iPhone precisam estar no mesmo Apple ID."))
                .font(.footnote).foregroundStyle(.secondary)
            if !CloudNotes.available {
                Text(tr("Este build do app não tem o iCloud: as notificações só vão com uma chave própria (abaixo)."))
                    .font(.footnote).foregroundStyle(.orange)
            }
            HStack {
                Text(String(format: tr("%d aparelho(s) recebem"), push.receiving)).font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Button(tr("Mandar um teste")) { push.test() }.disabled(!push.reachable)
            }
            DisclosureGroup(tr("Chave própria da Apple (avançado)")) {
                Text(tr("Para quem compila o app do iPhone com a própria conta de desenvolvedor: o Mac manda direto para a Apple com uma chave APNs dessa conta (developer.apple.com → Keys). Um iPhone com essa chave não usa o iCloud."))
                    .font(.footnote).foregroundStyle(.secondary)
                TextField(tr("Key ID"), text: prefs.bind({ Push.keyId }, { UserDefaults.standard.set($0.trimmingCharacters(in: .whitespaces), forKey: "pushKeyId") }))
                TextField(tr("Team ID"), text: prefs.bind({ Push.teamId }, { UserDefaults.standard.set($0.trimmingCharacters(in: .whitespaces), forKey: "pushTeamId") }))
                HStack {
                    Button(tr("Escolher a chave .p8…")) {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.init(filenameExtension: "p8") ?? .data]
                        guard panel.runModal() == .OK, let url = panel.url else { return }
                        do { try Push.setKey(from: url); keyError = nil } catch { keyError = tr("Não é uma chave .p8 válida.") }
                        prefs.refresh()
                    }
                    Text(FileManager.default.fileExists(atPath: Push.keyFile.path) ? tr("chave guardada") : tr("sem chave"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let keyError { Text(keyError).font(.footnote).foregroundStyle(.red) }
            }
        }
    }

    static func qr(_ text: String) -> NSImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(text.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let img = f.outputImage else { return nil }
        let rep = NSCIImageRep(ciImage: img.transformed(by: CGAffineTransform(scaleX: 8, y: 8)))
        let out = NSImage(size: rep.size)
        out.addRepresentation(rep)
        return out
    }
}
