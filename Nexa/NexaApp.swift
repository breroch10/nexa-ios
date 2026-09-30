import SwiftUI

@main
struct NexaApp: App {
    @StateObject private var conversa = Conversa.shared
    @Environment(\.scenePhase) private var fase

    var body: some Scene {
        WindowGroup {
            TelaPrincipal()
                .environmentObject(conversa)
                .preferredColorScheme(.dark)
                .onOpenURL { conversa.abriuURL($0) }
        }
        .onChange(of: fase) { _, nova in
            if nova == .active { conversa.ficouAtivo() }
        }
    }
}
