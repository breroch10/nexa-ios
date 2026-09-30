import Foundation

/// WebSocket com a ponte da Nexa na VPS (rede privada Tailscale).
/// Manda PCM16 16 kHz binário; recebe JSON (texto) e PCM16 24 kHz (binário).
/// Todos os avisos chegam na main, na ordem em que vieram.
final class Ponte: NSObject, URLSessionWebSocketDelegate {
    static let endereco = URL(string: "wss://beup-vps.tail76dcad.ts.net:8444/ws?aparelho=iphone-app")!
    static let origem = "https://beup-vps.tail76dcad.ts.net:8444"

    var aoAbrir: (@MainActor () -> Void)?
    var aoTexto: (@MainActor (String) -> Void)?
    var aoAudio: (@MainActor (Data) -> Void)?
    /// código de fechamento (1000 normal, 1008 origem recusada, negativo = rede) e o motivo
    var aoFechar: (@MainActor (Int, String) -> Void)?

    private let trava = NSLock()
    private var tarefa: URLSessionWebSocketTask?
    private var aberta = false
    private var _ultimoSinal: TimeInterval = 0

    private lazy var sessao: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 300          // quem vigia a conexão é o ping (10 s) e a Conversa
        c.waitsForConnectivity = false
        let fila = OperationQueue()
        fila.maxConcurrentOperationCount = 1
        return URLSession(configuration: c, delegate: self, delegateQueue: fila)
    }()

    /// Última vez que chegou qualquer coisa da ponte (mensagem ou pong).
    var ultimoSinal: TimeInterval { trava.lock(); defer { trava.unlock() }; return _ultimoSinal }

    private static var agora: TimeInterval { ProcessInfo.processInfo.systemUptime }

    func conectar() {
        fechar()
        var req = URLRequest(url: Ponte.endereco)
        req.setValue(Ponte.origem, forHTTPHeaderField: "Origin")
        let t = sessao.webSocketTask(with: req)
        t.maximumMessageSize = 8 << 20
        trava.lock()
        tarefa = t
        aberta = false
        _ultimoSinal = Ponte.agora
        trava.unlock()
        t.resume()
        receber(t)
    }

    /// Fecha sem avisar ninguém (quem fechou já sabe).
    func fechar() {
        trava.lock()
        let t = tarefa
        tarefa = nil
        aberta = false
        trava.unlock()
        t?.cancel(with: .normalClosure, reason: nil)
    }

    /// Fecha e avisa como queda (conexão parada sem resposta).
    func derrubar() {
        trava.lock()
        let t = tarefa
        trava.unlock()
        guard let t else { return }
        terminou(t, codigo: -2, razao: "sem resposta")
        t.cancel(with: .goingAway, reason: nil)
    }

    func enviar(_ d: Data) {
        trava.lock()
        let t = aberta ? tarefa : nil
        trava.unlock()
        t?.send(.data(d)) { _ in }
    }

    func enviar(texto: String) {
        trava.lock()
        let t = aberta ? tarefa : nil
        trava.unlock()
        t?.send(.string(texto)) { _ in }
    }

    func ping() {
        trava.lock()
        let t = aberta ? tarefa : nil
        trava.unlock()
        guard let t else { return }
        t.sendPing { [weak self] erro in
            guard let self else { return }
            if erro == nil {
                self.trava.lock(); self._ultimoSinal = Ponte.agora; self.trava.unlock()
            }
        }
    }

    private func atual(_ t: URLSessionWebSocketTask) -> Bool {
        trava.lock(); defer { trava.unlock() }
        return tarefa === t
    }

    private func receber(_ t: URLSessionWebSocketTask) {
        t.receive { [weak self] r in
            guard let self, self.atual(t) else { return }
            switch r {
            case .success(let m):
                self.trava.lock(); self._ultimoSinal = Ponte.agora; self.trava.unlock()
                switch m {
                case .data(let d):
                    DispatchQueue.main.async { MainActor.assumeIsolated { if self.atual(t) { self.aoAudio?(d) } } }
                case .string(let s):
                    DispatchQueue.main.async { MainActor.assumeIsolated { if self.atual(t) { self.aoTexto?(s) } } }
                @unknown default:
                    break
                }
                self.receber(t)
            case .failure(let e):
                let codigo = t.closeCode == .invalid ? -1 : t.closeCode.rawValue
                self.terminou(t, codigo: codigo, razao: Ponte.razao(t) ?? e.localizedDescription)
            }
        }
    }

    private static func razao(_ t: URLSessionWebSocketTask) -> String? {
        t.closeReason.flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Avisa a queda uma vez só por conexão.
    private func terminou(_ t: URLSessionWebSocketTask, codigo: Int, razao: String) {
        trava.lock()
        guard tarefa === t else { trava.unlock(); return }
        tarefa = nil
        aberta = false
        trava.unlock()
        DispatchQueue.main.async { MainActor.assumeIsolated { self.aoFechar?(codigo, razao) } }
    }

    // MARK: URLSessionWebSocketDelegate

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        trava.lock()
        let ok = tarefa === webSocketTask
        if ok { aberta = true; _ultimoSinal = Ponte.agora }
        trava.unlock()
        if ok { DispatchQueue.main.async { MainActor.assumeIsolated { self.aoAbrir?() } } }
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        terminou(webSocketTask, codigo: closeCode.rawValue, razao: reason.flatMap { String(data: $0, encoding: .utf8) } ?? "")
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let t = task as? URLSessionWebSocketTask else { return }
        let codigo = t.closeCode == .invalid ? -1 : t.closeCode.rawValue
        terminou(t, codigo: codigo, razao: Ponte.razao(t) ?? error?.localizedDescription ?? "")
    }
}
