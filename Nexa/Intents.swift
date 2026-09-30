import AppIntents

/// "Nexa" / "Falar com a Nexa": abre o app e já começa a ouvir.
/// Aparece no app Atalhos, na Siri e em Ajustes > Acessibilidade > Atalhos Vocais.
struct ConversarComNexa: AppIntent {
    static var title: LocalizedStringResource = "Conversar com a Nexa"
    static var description = IntentDescription("Abre a Nexa e já começa a ouvir.")
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        Conversa.shared.pedirLigar()
        return .result()
    }
}

/// Encerra a conversa e desliga o microfone, sem abrir o app.
struct EncerrarNexa: AppIntent {
    static var title: LocalizedStringResource = "Encerrar a conversa com a Nexa"
    static var description = IntentDescription("Desliga o microfone e encerra a conversa com a Nexa.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        Conversa.shared.desligar(motivo: "Conversa encerrada")
        return .result()
    }
}

struct AtalhosNexa: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ConversarComNexa(),
            phrases: [
                "\(.applicationName)",
                "Falar com a \(.applicationName)",
                "Conversar com a \(.applicationName)",
                "Chamar a \(.applicationName)",
            ],
            shortTitle: "Conversar",
            systemImageName: "waveform.circle"
        )
        AppShortcut(
            intent: EncerrarNexa(),
            phrases: [
                "Encerrar a \(.applicationName)",
                "Desligar a \(.applicationName)",
            ],
            shortTitle: "Encerrar",
            systemImageName: "stop.circle"
        )
    }
}
