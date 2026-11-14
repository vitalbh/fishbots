import AppKit
import CoreImage
import SwiftUI

/// Preferences → General → Other devices: the switch for Remote.swift, and the QR code a phone scans to pair.
struct RemotePairingSection: View {
    @ObservedObject var prefs: Prefs
    let remote: Remote
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
                        Button(tr("Esquecer aparelhos")) { remote.forgetDevices(); prefs.refresh() }
                        Text(tr("Troca a chave: os aparelhos pareados precisam ler o código de novo."))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .task { tailscale = await remote.refreshTailscale() }
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
