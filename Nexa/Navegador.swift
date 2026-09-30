import SafariServices
import UIKit

/// Abre a tela completa (v2) ou um link num Safari por cima do app. O botão Fechar do próprio Safari volta pra Nexa.
@MainActor
enum Navegador {
    static func abrir(_ url: URL) {
        guard let esquema = url.scheme?.lowercased(), esquema == "https" || esquema == "http" else {
            UIApplication.shared.open(url)
            return
        }
        let cenas = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let cena = cenas.first { $0.activationState == .foregroundActive } ?? cenas.first
        guard let janela = cena?.windows.first(where: { $0.isKeyWindow }) ?? cena?.windows.first,
              var topo = janela.rootViewController else { return }
        while let p = topo.presentedViewController { topo = p }

        let cfg = SFSafariViewController.Configuration()
        cfg.barCollapsingEnabled = true
        cfg.entersReaderIfAvailable = false
        let vc = SFSafariViewController(url: url, configuration: cfg)
        vc.preferredControlTintColor = Paleta.laranjaRGB.ui
        vc.preferredBarTintColor = Paleta.fundoRGB.ui
        vc.dismissButtonStyle = .close
        vc.overrideUserInterfaceStyle = .dark
        vc.modalPresentationStyle = .pageSheet

        if topo is SFSafariViewController, let quem = topo.presentingViewController {
            topo.dismiss(animated: false) { quem.present(vc, animated: true) }
        } else {
            topo.present(vc, animated: true)
        }
    }
}
