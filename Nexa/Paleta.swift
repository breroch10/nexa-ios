import SwiftUI
import UIKit

/// Cor em RGB linear simples, pra misturar teal e laranja quadro a quadro.
struct RGB {
    var r: Double, g: Double, b: Double

    init(_ hex: UInt32) {
        r = Double((hex >> 16) & 0xff) / 255
        g = Double((hex >> 8) & 0xff) / 255
        b = Double(hex & 0xff) / 255
    }
    init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }

    func misturar(_ o: RGB, _ t: Double) -> RGB {
        let k = max(0, min(1, t))
        return RGB(r: r + (o.r - r) * k, g: g + (o.g - g) * k, b: b + (o.b - b) * k)
    }
    var cor: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
    var ui: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
}

enum Paleta {
    static let fundoRGB = RGB(0x020b0e)
    static let laranjaRGB = RGB(0xff7a2f)
    static let laranjaFundoRGB = RGB(0xe8622f)
    static let tealRGB = RGB(0x6fd3c7)
    static let areiaRGB = RGB(0xebe2dd)

    static let fundo = fundoRGB.cor
    static let laranja = laranjaRGB.cor
    static let laranjaFundo = laranjaFundoRGB.cor
    static let teal = tealRGB.cor
    static let texto = areiaRGB.cor
}
