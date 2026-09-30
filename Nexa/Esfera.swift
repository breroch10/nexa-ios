import SwiftUI

/// Valores suavizados quadro a quadro (cor, brilho, espessura, níveis).
final class AnimEsfera {
    private var ultimo: Double = 0
    private(set) var tempo: Double = 0
    private(set) var mic: Double = 0
    private(set) var saida: Double = 0
    private(set) var calor: Double = 1        // 0 = teal (ouvindo), 1 = laranja (falando)
    private(set) var brilho: Double = 0.45
    private(set) var espessura: Double = 2
    private(set) var arco: Double = 0         // anel girando (conectando, pensando)
    private(set) var giro: Double = 0

    var nivel: Double { max(mic, saida) }

    func passo(_ agora: Double, estado: Conversa.Estado, mic m: Float, saida s: Float) {
        let dt = ultimo == 0 ? 1.0 / 60 : min(0.1, max(0, agora - ultimo))
        ultimo = agora
        tempo += dt
        func env(_ v: Double, _ alvo: Double) -> Double {       // envelope da página: sobe em 30 ms, desce em 220 ms
            let tau = alvo > v ? 0.03 : 0.22
            return v + (alvo - v) * (1 - exp(-dt / tau))
        }
        mic = env(mic, estado == .ouvindo || estado == .pensando ? Double(m) : 0)
        saida = env(saida, estado == .falando ? Double(s) : 0)

        let alvo: (calor: Double, brilho: Double, esp: Double, arco: Double)
        switch estado {
        case .repouso:    alvo = (1.00, 0.42, 2.0, 0)
        case .conectando: alvo = (0.55, 0.55, 1.6, 1)
        case .ouvindo:    alvo = (0.00, 0.66, 1.3, 0)
        case .pensando:   alvo = (0.80, 0.72, 2.2, 1)
        case .falando:    alvo = (1.00, 1.00, 3.6, 0)
        case .erro:       alvo = (1.00, 0.28, 1.4, 0)
        }
        let k = 1 - exp(-dt / 0.28)
        calor += (alvo.calor - calor) * k
        brilho += (alvo.brilho - brilho) * k
        espessura += (alvo.esp - espessura) * k
        arco += (alvo.arco - arco) * k
        giro += dt * (0.9 + 1.6 * arco)
    }
}

/// A esfera: anel de luz orgânico que respira em repouso, fica teal fino ouvindo e laranja forte falando.
struct Esfera: View {
    let estado: Conversa.Estado
    let medidor: Medidor
    @State private var anim = AnimEsfera()

    var body: some View {
        TimelineView(.animation(minimumInterval: estado == .repouso || estado == .erro ? 1.0 / 30 : nil)) { tl in
            Canvas { ctx, size in
                anim.passo(tl.date.timeIntervalSinceReferenceDate, estado: estado, mic: medidor.mic, saida: medidor.saida)
                desenhar(&ctx, size)
            }
        }
    }

    private func desenhar(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let a = anim
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        let base = min(size.width, size.height) * 0.30
        let respira = 0.015 * sin(a.tempo * 1.4) * (1 - a.nivel)
        let r = base * (1 + 0.12 * a.nivel + respira)
        let rgb = Paleta.tealRGB.misturar(Paleta.laranjaRGB, a.calor)
        let cor = rgb.cor
        let nucleo = rgb.misturar(RGB(r: 1, g: 0.97, b: 0.92), 0.45).cor
        let anel = caminho(c, r, deform: 0.010 + 0.055 * a.nivel, t: a.tempo)

        // halo de fundo
        let halo = Path(ellipseIn: CGRect(x: c.x - r * 1.9, y: c.y - r * 1.9, width: r * 3.8, height: r * 3.8))
        ctx.fill(halo, with: .radialGradient(Gradient(colors: [cor.opacity(0.13 * a.brilho), cor.opacity(0.04 * a.brilho), .clear]),
                                             center: c, startRadius: r * 0.3, endRadius: r * 1.9))
        // miolo escuro com um toque da cor
        let miolo = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
        ctx.fill(miolo, with: .radialGradient(Gradient(colors: [Paleta.fundo.opacity(0.9), cor.opacity(0.07 * a.brilho)]),
                                              center: c, startRadius: 0, endRadius: r))

        ctx.drawLayer { l in                                   // brilho largo
            l.addFilter(.blur(radius: 22))
            l.blendMode = .plusLighter
            l.stroke(anel, with: .color(cor.opacity(0.55 * a.brilho)), lineWidth: 10 + 22 * a.nivel)
        }
        ctx.drawLayer { l in                                   // brilho próximo
            l.addFilter(.blur(radius: 6))
            l.blendMode = .plusLighter
            l.stroke(anel, with: .color(cor.opacity(0.85 * a.brilho)), lineWidth: a.espessura * 2.6)
        }
        ctx.drawLayer { l in                                   // fio de luz
            l.blendMode = .plusLighter
            l.stroke(anel, with: .color(nucleo.opacity(0.25 + 0.75 * a.brilho)), lineWidth: a.espessura)
        }
        if a.arco > 0.02 {                                     // arco girando: conectando ou pensando
            let ini = a.giro * 2.2
            let arco = Path { p in
                p.addArc(center: c, radius: r, startAngle: .radians(ini), endAngle: .radians(ini + 1.2), clockwise: false)
            }
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 5))
                l.blendMode = .plusLighter
                l.stroke(arco, with: .color(nucleo.opacity(0.7 * a.arco)), style: StrokeStyle(lineWidth: 3.2, lineCap: .round))
            }
        }
    }

    /// Círculo com ondulação lenta (lembra o ícone); a ondulação cresce com a voz.
    private func caminho(_ c: CGPoint, _ r: Double, deform: Double, t: Double) -> Path {
        var p = Path()
        let n = 144
        for i in 0...n {
            let th = Double(i) / Double(n) * 2 * .pi
            let d = 1 + deform * (0.6 * sin(3 * th + t * 1.3) + 0.3 * sin(5 * th - t * 0.9 + 1.7) + 0.2 * sin(8 * th + t * 2.1))
            let pt = CGPoint(x: c.x + r * d * cos(th), y: c.y + r * d * sin(th))
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }
}
