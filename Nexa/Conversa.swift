import AVFoundation
import SwiftUI
import UIKit

struct Destaque: Equatable {
    let texto: String
    let url: URL
}

/// A conversa por voz com a ponte. Um só objeto pro app inteiro (a tela, o App Intent e os links nexa://).
@MainActor
final class Conversa: ObservableObject {
    static let shared = Conversa()
    static let telaCompleta = URL(string: "https://beup-vps.tail76dcad.ts.net:8444/v2/")!

    enum Estado { case repouso, conectando, ouvindo, pensando, falando, erro }

    @Published private(set) var estado: Estado = .repouso
    /// O que ela está dizendo (turno atual).
    @Published private(set) var legenda = ""
    /// Ferramenta rodando ("consultando o cérebro: ...").
    @Published private(set) var detalhe = ""
    @Published private(set) var aviso = ""
    /// Ela mostrou algo que só a tela completa desenha (telas, reels, criação).
    @Published var destaque: Destaque?

    let motor = AudioMotor()
    var medidor: Medidor { motor.medidor }
    private let ponte = Ponte()

    private(set) var ativa = false
    private var pronto = false, jaFicouPronto = false
    private var pensando = false, ferramenta = false
    private var turnoFechado = true, legendaNova = true, turnoComAudio = false, ouviAposFim = false
    private var vozEm: TimeInterval = 0, ultimaAtividade: TimeInterval = 0, conectouEm: TimeInterval = 0
    private var ultimoTique: TimeInterval = 0, ultimoPing: TimeInterval = 0
    private var duckT: Double = 0, duckAte: TimeInterval = 0
    private var quedas: [TimeInterval] = []
    private var ultimoErro = "", ultimoErroEm: TimeInterval = 0
    private var relogio: Timer?
    private var ligarAoAtivar = false
    private var acaoPendente: URL?
    private var avisoN = 0
    private var sessaoN = 0                      // cada ligar() ganha um número; um abrir() velho não mexe na conversa nova
    private let tato = UIImpactFeedbackGenerator(style: .soft)

    /// 15 minutos sem ninguém falar: encerra (bateria e privacidade).
    private let limiteParada: TimeInterval = 15 * 60

    private static var agora: TimeInterval { ProcessInfo.processInfo.systemUptime }

    private init() {
        let p = ponte
        motor.aoCapturar = { d in p.enviar(d) }
        motor.aoFalhar = { [weak self] m in self?.desligar(motivo: m, erro: true) }
        ponte.aoTexto = { [weak self] s in self?.recebeu(texto: s) }
        ponte.aoAudio = { [weak self] d in self?.recebeu(audio: d) }
        ponte.aoFechar = { [weak self] c, r in self?.caiu(codigo: c, razao: r) }
        // Além do scenePhase: na abertura a frio pelo App Intent o scenePhase pode já nascer ativo e não avisar a mudança.
        // Chamar ficouAtivo() duas vezes não faz mal (as duas pendências se zeram na primeira).
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Conversa.shared.ficouAtivo() }
        }
    }

    // MARK: ligar e desligar

    func alternar() {
        if ativa { desligar(motivo: "") } else { ligar() }
    }

    /// Pedido do App Intent ou de nexa://ouvir: liga assim que o app estiver na frente.
    func pedirLigar() {
        if UIApplication.shared.applicationState == .active {
            ligar()
        } else {
            ligarAoAtivar = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                MainActor.assumeIsolated {
                    let c = Conversa.shared
                    if c.ligarAoAtivar && UIApplication.shared.applicationState == .active { c.ligarAoAtivar = false; c.ligar() }
                }
            }
        }
    }

    func ficouAtivo() {
        if ligarAoAtivar { ligarAoAtivar = false; ligar() }
        if let u = acaoPendente { acaoPendente = nil; UIApplication.shared.open(u) }
    }

    func ligar() {
        guard !ativa else { return }
        ativa = true
        pronto = false; jaFicouPronto = false; quedas = []
        zerarTurno()
        legenda = ""; detalhe = ""; destaque = nil
        estado = .conectando
        tato.impactOccurred()
        sessaoN += 1
        let n = sessaoN
        Task { await self.abrir(n) }
    }

    private func abrir(_ n: Int) async {
        let pode = await Conversa.permissaoMic()
        guard ativa, n == sessaoN else { return }
        guard pode else {
            desligar(motivo: "Microfone bloqueado. Abra Ajustes, Nexa, e libere o microfone.", erro: true)
            return
        }
        ponte.conectar()
        conectouEm = Conversa.agora
        do {
            try motor.iniciar()
        } catch {
            desligar(motivo: "Não deu pra abrir o áudio. Toque de novo.", erro: true)
            return
        }
        ultimaAtividade = Conversa.agora
        ultimoTique = 0
        relogio?.invalidate()
        let t = Timer(timeInterval: 0.05, repeats: true) { _ in
            MainActor.assumeIsolated { Conversa.shared.tique() }
        }
        RunLoop.main.add(t, forMode: .common)
        relogio = t
    }

    static func permissaoMic() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    func desligar(motivo: String, erro: Bool = false) {
        guard ativa else { return }
        ativa = false
        relogio?.invalidate(); relogio = nil
        ponte.fechar()
        motor.parar()
        pronto = false; jaFicouPronto = false; quedas = []
        zerarTurno()
        detalhe = ""
        duckAte = 0; duckT = 0
        estado = erro ? .erro : .repouso
        if !motivo.isEmpty { avisar(motivo, segundos: erro ? 6 : 4) }
        tato.impactOccurred(intensity: 0.6)
        if erro {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                MainActor.assumeIsolated {
                    let c = Conversa.shared
                    if !c.ativa && c.estado == .erro { c.estado = .repouso }
                }
            }
        }
    }

    private func zerarTurno() {
        pensando = false; ferramenta = false
        turnoFechado = true; legendaNova = true; turnoComAudio = false; ouviAposFim = false
    }

    // MARK: o que chega da ponte

    private func recebeu(audio d: Data) {
        guard ativa else { return }
        pensando = false; ferramenta = false
        if !detalhe.isEmpty { detalhe = "" }
        // resposta nova chegando com a anterior ainda tocando, e tu falou depois do fim dela: a antiga sai
        if !turnoComAudio && ouviAposFim && motor.tocando { motor.pararFala() }
        ouviAposFim = false
        turnoComAudio = true
        turnoFechado = false
        motor.tocar(d)
        ultimaAtividade = Conversa.agora
    }

    private func recebeu(texto s: String) {
        guard ativa, let dado = s.data(using: .utf8),
              let j = (try? JSONSerialization.jsonObject(with: dado)) as? [String: Any],
              let tipo = j["tipo"] as? String else { return }
        let texto = j["texto"] as? String ?? ""
        let t = Conversa.agora
        switch tipo {
        case "pronto":
            let primeira = !jaFicouPronto
            pronto = true; jaFicouPronto = true
            ultimaAtividade = t
            if primeira { motor.som(.ouvir) } else { avisar("Reconectado") }
        case "ouvi":
            pensando = true
            ultimaAtividade = t
            if turnoFechado && motor.tocando {
                ouviAposFim = true
                // ela já terminou de gerar e ainda toca o resto; tu falou por cima: corta sem esperar o buffer acabar
                if t - vozEm < 2.5 { motor.pararFala() }
            }
        case "pensando":
            pensando = true; ferramenta = true
            ultimaAtividade = t
            if !texto.isEmpty { detalhe = String(texto.prefix(90)) }
        case "disse":
            if legendaNova { legenda = ""; legendaNova = false }
            legenda = Conversa.encurtar(legenda + texto)
            turnoFechado = false
            ultimaAtividade = t
        case "interrompido":
            motor.pararFala()
            fecharTurno()
        case "fim":
            fecharTurno()
            detalhe = ""
        case "erro":
            let msg = texto.isEmpty ? "A ponte avisou um erro." : texto
            ultimoErro = msg; ultimoErroEm = t
            avisar(msg, segundos: 6)
        case "tela", "abrir":
            destaque = Destaque(texto: "Ver na tela completa", url: Conversa.telaCompleta)
        case "reels":
            destaque = Destaque(texto: "Ver os reels", url: Conversa.telaCompleta)
        case "criacao":
            let titulo = (j["titulo"] as? String) ?? "criação"
            if let l = j["link"] as? String, let u = URL(string: l), u.scheme?.hasPrefix("http") == true {
                destaque = Destaque(texto: "Abrir \(titulo)", url: u)
            } else if let passo = j["passo"] as? String, !passo.isEmpty {
                avisar("Criando \(titulo): \(passo)")
            }
        case "resultado_pronto":
            let titulo = (j["titulo"] as? String) ?? ""
            avisar(titulo.isEmpty ? "Tem resultado pronto. Ela conta na próxima pausa." : "Pronto: \(titulo). Ela conta na próxima pausa.")
        case "iphone":
            acaoIphone(j)
        default:
            break
        }
    }

    private func fecharTurno() {
        pensando = false; ferramenta = false
        turnoFechado = true; legendaNova = true; turnoComAudio = false
    }

    private func caiu(codigo: Int, razao: String) {
        guard ativa else { return }
        let t = Conversa.agora
        motor.pararFala()
        fecharTurno()
        pronto = false
        quedas = quedas.filter { t - $0 < 60 }
        // caiu no meio de uma conversa que estava de pé (rede trocou, ponte reiniciou): tenta de novo, até 3 vezes por minuto
        if jaFicouPronto && codigo != 1000 && codigo != 1008 && quedas.count < 3 {
            quedas.append(t)
            avisar("A conexão caiu, reconectando")
            let atraso = 0.4 + Double(quedas.count - 1) * 1.2
            conectouEm = t + atraso                       // o vigia de 20 s conta a partir da nova tentativa
            DispatchQueue.main.asyncAfter(deadline: .now() + atraso) {
                MainActor.assumeIsolated {
                    let c = Conversa.shared
                    guard c.ativa, !c.pronto else { return }
                    c.ponte.conectar()
                    c.conectouEm = Conversa.agora
                }
            }
            return
        }
        let motivo: String
        if t - ultimoErroEm < 5 && !ultimoErro.isEmpty { motivo = ultimoErro }
        else if codigo == 1008 { motivo = "A ponte recusou a conexão (origem fora da lista)." }
        else if !jaFicouPronto { motivo = "A ponte não respondeu. Confira se o Tailscale está ligado." }
        else { motivo = "A conexão caiu. Toque pra conversar de novo." }
        desligar(motivo: motivo, erro: true)
    }

    // MARK: relógio (20 por segundo): estado, duck, ping e vigias

    private func tique() {
        guard ativa else { return }
        let t = Conversa.agora
        let dt = ultimoTique == 0 ? 0.05 : min(0.25, t - ultimoTique)
        ultimoTique = t
        let mic = Double(medidor.mic)
        if mic > 0.27 { vozEm = t; ultimaAtividade = t }
        let falando = motor.tocando
        if falando { ultimaAtividade = t }

        // duck: tu falando por cima dela por 120 ms abaixa a voz dela; sem 'interrompido' em 700 ms, volta
        if falando && duckAte == 0 {
            duckT = (mic > 0.45 && mic > Double(medidor.saida) * 0.5) ? duckT + dt : 0
            if duckT >= 0.12 { motor.abaixar(true); duckAte = t + 0.7; duckT = 0 }
        } else if duckAte > 0 && (t > duckAte || !falando) {
            motor.abaixar(false); duckAte = 0
        }

        if pronto && t - ultimoPing > 10 { ultimoPing = t; ponte.ping() }
        if pronto && t - ponte.ultimoSinal > 35 { ponte.derrubar(); return }
        if !pronto && t - conectouEm > 20 {
            ponte.fechar()
            caiu(codigo: -3, razao: "demorou")
            return
        }
        if t - ultimaAtividade > limiteParada {
            desligar(motivo: "Conversa encerrada depois de 15 minutos parada.")
            return
        }

        let novo: Estado
        if !pronto { novo = .conectando }
        else if falando { novo = .falando }
        else if pensando && (ferramenta || t - vozEm > 0.35) { novo = .pensando }
        else { novo = .ouvindo }
        if novo != estado { estado = novo }
    }

    // MARK: avisos e links

    func avisar(_ texto: String, segundos: Double = 4) {
        avisoN += 1
        let n = avisoN
        aviso = texto
        DispatchQueue.main.asyncAfter(deadline: .now() + segundos) {
            MainActor.assumeIsolated {
                let c = Conversa.shared
                if c.avisoN == n { c.aviso = "" }
            }
        }
    }

    static func encurtar(_ s: String) -> String {
        let limite = 220
        guard s.count > limite else { return s }
        let fim = s.suffix(limite)
        if let i = fim.firstIndex(of: " ") { return "…" + fim[fim.index(after: i)...] }
        return String(fim)
    }

    /// nexa://ouvir (ou nexa://conversar) liga, nexa://encerrar desliga, nexa://tela abre a tela completa.
    func abriuURL(_ url: URL) {
        guard url.scheme?.lowercased() == "nexa" else { return }
        switch (url.host ?? "").lowercased() {
        case "ouvir", "conversar", "falar": pedirLigar()
        case "encerrar", "parar": desligar(motivo: "Conversa encerrada")
        case "tela": Navegador.abrir(Conversa.telaCompleta)
        default: break
        }
    }

    // MARK: ações no iPhone

    /// {tipo:'iphone', acao:'atalho', nome, entrada?} roda o Atalho com esse nome e volta pra Nexa.
    /// {tipo:'iphone', acao:'abrir', url} abre a URL.
    private func acaoIphone(_ j: [String: Any]) {
        guard let url = Conversa.urlDaAcao(j) else { return }
        if let nome = j["nome"] as? String { avisar("Rodando o atalho \(nome)") }
        if UIApplication.shared.applicationState == .active {
            UIApplication.shared.open(url) { ok in
                if !ok { MainActor.assumeIsolated { Conversa.shared.avisar("Não consegui abrir isso no iPhone.") } }
            }
        } else {
            acaoPendente = url
            avisar("Desbloqueie o iPhone pra eu terminar isso.", segundos: 8)
        }
    }

    static func urlDaAcao(_ j: [String: Any]) -> URL? {
        switch j["acao"] as? String {
        case "atalho":
            guard let nome = j["nome"] as? String, !nome.isEmpty else { return nil }
            var q = "name=" + codificar(nome)
            if let e = j["entrada"], !(e is NSNull) {
                let texto: String
                if let s = e as? String { texto = s }
                else if JSONSerialization.isValidJSONObject(e), let d = try? JSONSerialization.data(withJSONObject: e),
                        let s = String(data: d, encoding: .utf8) { texto = s }
                else { texto = "\(e)" }
                q += "&input=text&text=" + codificar(texto)
            }
            let volta = codificar("nexa://voltar")
            q += "&x-success=\(volta)&x-cancel=\(volta)&x-error=\(volta)"
            return URL(string: "shortcuts://x-callback-url/run-shortcut?" + q)
        case "abrir":
            guard let s = j["url"] as? String, let u = URL(string: s), u.scheme != nil else { return nil }
            return u
        default:
            return nil
        }
    }

    static func codificar(_ s: String) -> String {
        let ok = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return s.addingPercentEncoding(withAllowedCharacters: ok) ?? s
    }
}
