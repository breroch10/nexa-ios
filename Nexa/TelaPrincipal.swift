import SwiftUI

struct TelaPrincipal: View {
    @EnvironmentObject private var conversa: Conversa

    var body: some View {
        ZStack {
            Paleta.fundo.ignoresSafeArea()
            VStack(spacing: 0) {
                topo
                Spacer(minLength: 8)
                Esfera(estado: conversa.estado, medidor: conversa.medidor)
                    .frame(width: 340, height: 340)
                    .contentShape(Circle().inset(by: 50))
                    .onTapGesture { conversa.alternar() }
                    .accessibilityElement()
                    .accessibilityLabel(conversa.ativa ? "Encerrar a conversa" : "Conversar com a Nexa")
                    .accessibilityAddTraits(.isButton)
                rotulo
                    .padding(.top, 2)
                legenda
                    .padding(.horizontal, 30)
                    .padding(.top, 22)
                Spacer(minLength: 8)
                rodape
            }
        }
        .animation(.easeOut(duration: 0.25), value: conversa.aviso)
        .animation(.easeOut(duration: 0.25), value: conversa.destaque)
    }

    private var topo: some View {
        ZStack {
            Text("NEXA")
                .font(.system(size: 15, weight: .semibold))
                .tracking(9)
                .foregroundStyle(Paleta.texto.opacity(0.92))
            HStack {
                Spacer()
                Button { Navegador.abrir(Conversa.telaCompleta) } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Paleta.texto.opacity(0.7))
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Tela completa")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private var rotulo: some View {
        Text(textoEstado.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(2.4)
            .foregroundStyle(corEstado)
            .lineLimit(1)
            .padding(.horizontal, 24)
            .contentTransition(.opacity)
            .animation(.easeOut(duration: 0.2), value: textoEstado)
    }

    private var textoEstado: String {
        switch conversa.estado {
        case .repouso: return "Toque pra conversar"
        case .conectando: return "Conectando"
        case .ouvindo: return "Ouvindo"
        case .pensando: return conversa.detalhe.isEmpty ? "Pensando" : conversa.detalhe
        case .falando: return "Falando"
        case .erro: return "Toque pra tentar de novo"
        }
    }

    private var corEstado: Color {
        switch conversa.estado {
        case .ouvindo: return Paleta.teal.opacity(0.9)
        case .falando, .pensando: return Paleta.laranja.opacity(0.9)
        case .erro: return Paleta.laranjaFundo.opacity(0.8)
        default: return Paleta.texto.opacity(0.45)
        }
    }

    private var legenda: some View {
        Text(conversa.legenda)
            .font(.system(size: 21, weight: .light))
            .foregroundStyle(Paleta.texto.opacity(0.95))
            .multilineTextAlignment(.center)
            .lineSpacing(5)
            .lineLimit(6)
            .frame(maxWidth: .infinity, minHeight: 150, maxHeight: 190, alignment: .top)
            .mask(
                LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0), .init(color: .black, location: 0.3),
                                       .init(color: .black, location: 1)], startPoint: .top, endPoint: .bottom)
            )
            .animation(.easeOut(duration: 0.15), value: conversa.legenda)
    }

    private var rodape: some View {
        VStack(spacing: 12) {
            if !conversa.aviso.isEmpty {
                Text(conversa.aviso)
                    .font(.system(size: 13))
                    .foregroundStyle(Paleta.texto.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .transition(.opacity)
            }
            if let d = conversa.destaque {
                Button {
                    conversa.destaque = nil
                    Navegador.abrir(d.url)
                } label: {
                    Label(d.texto, systemImage: "sparkles")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Paleta.fundo)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(Paleta.laranja))
                }
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
            Button { Navegador.abrir(Conversa.telaCompleta) } label: {
                Text("Tela completa")
                    .font(.system(size: 14, weight: .medium))
                    .tracking(0.4)
                    .foregroundStyle(Paleta.texto.opacity(0.8))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(Capsule().strokeBorder(Paleta.texto.opacity(0.18), lineWidth: 1))
            }
        }
        .padding(.bottom, 20)
    }
}
