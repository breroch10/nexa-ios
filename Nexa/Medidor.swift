import Foundation

/// Níveis 0..1 do microfone e da voz dela. Escritos na thread de áudio, lidos na tela.
final class Medidor {
    private let trava = NSLock()
    private var _mic: Float = 0
    private var _saida: Float = 0

    var mic: Float {
        get { trava.lock(); defer { trava.unlock() }; return _mic }
        set { trava.lock(); _mic = newValue; trava.unlock() }
    }
    var saida: Float {
        get { trava.lock(); defer { trava.unlock() }; return _saida }
        set { trava.lock(); _saida = newValue; trava.unlock() }
    }

    /// Mesma escala da página: -52 dB = 0, -18 dB = 1.
    static func nivel(_ p: UnsafePointer<Float>, _ n: Int) -> Float {
        guard n > 0 else { return 0 }
        var s: Float = 0
        for i in 0..<n { s += p[i] * p[i] }
        let db = 10 * log10(s / Float(n) + 1e-12)
        return min(1, max(0, (db + 52) / 34))
    }
}
