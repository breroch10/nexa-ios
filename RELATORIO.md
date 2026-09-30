---
title: "Nexa iOS v1: relatório"
data: 2026-09-29
area: "[[Vibing-Code]]"
tags: [vibing-code, ia-negocios, nexa, ios]
---

# Nexa iOS v1: relatório (29/09/2026, 22h)

## Status

- **Código do app: pronto** e checado localmente (compilação de tipos Swift contra o SDK iOS 26 no modo Catalyst, zero erro).
- **Repositório privado criado**: https://github.com/breroch10/nexa-ios (branch `main`, workflow `Build Nexa`).
- **Build na nuvem: BLOQUEADO pela cobrança do GitHub.** Os 2 builds pararam antes de começar (startup failure, custo zero) com o aviso:
  "The job was not started because recent account payments have failed or your spending limit needs to be increased."
  Em Ajustes > Billing > Budgets and alerts, a conta tem um orçamento de **Actions = US$ 0 com "Stop usage"**. Em repositório privado isso trava o runner de macOS.
- **Nexa.ipa: ainda não existe.** Sai assim que um dos dois desbloqueios abaixo for feito.

## O que o Breno precisa decidir (um dos dois)

1. **Deixar o repositório público** (Actions é grátis e sem limite em repositório público; o código não tem senha nem chave, só o endereço da ponte, que só abre dentro da tua Tailscale):
   `gh repo edit breroch10/nexa-ios --visibility public --accept-visibility-change-consequences`
2. **Ou liberar o Actions na cobrança**: github.com/settings/billing/budgets, editar o orçamento "Actions" (hoje US$ 0 com Stop usage) e conferir Payment information. Cada build gasta uns 5 minutos de macOS.

Depois, um comando compila e baixa o `.ipa`:

```bash
cd "/Volumes/Extreme SSD Breno/Projetos Beup/nexa-ios" && ./compilar.sh
# resultado: /Volumes/Extreme SSD Breno/Projetos Beup/nexa-ios/build/Nexa.ipa
```

## O que o app faz

| Pedido | Como ficou |
|---|---|
| Conversa por voz nativa | AVAudioSession `.playAndRecord` + `.voiceChat` + `.defaultToSpeaker` + `.allowBluetooth`; AVAudioEngine com processamento de voz do iOS ligado (cancelamento de eco); microfone convertido pra PCM16 16 kHz em pedaços de 3200 bytes; voz dela PCM16 24 kHz em fila no AVAudioPlayerNode; `interrompido` para na hora |
| Interromper falando por cima | eco dela cancelado pelo iPhone, então tua voz chega limpa na ponte; duck (abaixa a voz dela pra 25% quando tu fala por cima); corte local quando ela já terminou de gerar e tu falou (mesma regra da v2) |
| Estados | repouso, conectando, ouvindo (teal fino), pensando (arco girando + texto da ferramenta), falando (laranja forte), erro |
| Acordar sem tocar | App Intent "Conversar com a Nexa" (frases "Nexa", "Falar com a Nexa", "Conversar com a Nexa", "Chamar a Nexa") + "Encerrar a conversa com a Nexa". Atalho Vocal "Nexa" no iOS 18 (passo a passo no README) |
| Segundo plano | `UIBackgroundModes audio`; conversa continua com a tela bloqueada; tocar na esfera desliga o microfone; encerra sozinha com 15 min parada; reconecta sozinha até 3x por minuto se a rede cair |
| Ações no iPhone | `{tipo:'iphone', acao:'atalho', nome, entrada?}` roda o Atalho pelo `shortcuts://x-callback-url/run-shortcut` e volta pra Nexa; `{tipo:'iphone', acao:'abrir', url}` abre a URL; iPhone bloqueado = roda quando desbloquear |
| Tela completa | botão abre a v2 (`/v2/`) num Safari por cima; `tela`, `abrir`, `reels` e `criacao` com link viram um botão laranja "Ver na tela completa" |
| Visual | fundo #020b0e, anel de luz orgânico em SwiftUI Canvas (lembra o ícone), wordmark NEXA, legenda do que ela diz, ícone 1024 px da v2 |
| Links | `nexa://ouvir`, `nexa://encerrar`, `nexa://tela` |

Protocolo da ponte respeitado sem mexer nela: `wss://beup-vps.tail76dcad.ts.net:8444/ws?aparelho=iphone-app` com `Origin: https://beup-vps.tail76dcad.ts.net:8444`, identidade pela Tailscale, ping a cada 10 s.

## O que falta (fora deste app)

- **Ponte**: ainda não existe ferramenta que mande `{tipo:'iphone', ...}`. O app já entende; falta a ponte ganhar uma ferramenta tipo `iphone_atalho(nome, entrada)` que chame `manda(tipo="iphone", acao="atalho", ...)` na conversa cujo aparelho é `iphone-app`.
- **Atalhos do Breno**: criar no app Atalhos os atalhos "Nexa Lembrete", "Nexa Alarme" etc. (lista no README).
- **Teste no aparelho**: nada foi testado num iPhone ainda (sem build). Pontos pra olhar no primeiro teste: volume da voz dela no alto-falante com `.voiceChat`, se o eco some mesmo no viva-voz, e se o Atalho Vocal aparece em Acessibilidade.
- **Apple ID grátis**: reinstalar a cada 7 dias pelo Sideloadly (ou "Automatic refresh").

## Verificação independente (29/09, 22h20)

- **Bloqueio confirmado na página do build**: anotação do GitHub "The job was not started because recent account payments have failed or your spending limit needs to be increased". Não é erro no workflow (YAML válido). Repositório segue privado. Nenhum build rodou, custo zero.
- **Código lido inteiro** contra a tarefa e o protocolo da ponte (`atender` em ponte.py, conversa.js): áudio de ida PCM16 16 kHz em 3200 bytes, volta PCM16 24 kHz em fila, `Origin` na lista, `interrompido` para a voz na hora, eventos `pronto/ouvi/disse/pensando/fim/erro/tela/abrir/reels/criacao` tratados, zero travessão no texto da interface.
- **Corrigido**:
  1. Captura do microfone: o estado da conversão (conversor e sobra de bytes) era compartilhado entre o motor velho e o novo quando o áudio é refeito (fone entrando, ligação). Um tap atrasado podia mexer no mesmo array que a main estava zerando, risco de crash. Agora cada motor tem o seu.
  2. Se o motor de áudio não sobe, a sessão de gravação era deixada ativa. Agora é desligada no erro.
  3. App Intent: além do `scenePhase`, o app escuta `didBecomeActive` pra começar a ouvir mesmo quando abre a frio e o `scenePhase` já nasce ativo.
  4. `compilar.sh` pega só o build que ele mesmo disparou (antes podia pegar um build de push ou um anterior) e confere que o `.ipa` tem `Payload/Nexa.app/Nexa`.
- **Checagem de tipos** de novo depois das correções (Swift 6.3, SDK iOS 26 modo Catalyst, alvo iOS 17): zero erro.
- **Pra olhar no primeiro build de verdade**: a frase só "Nexa" no `AppShortcutsProvider` (se o processador de App Intents do Xcode reclamar, tirar essa frase; o Atalho Vocal continua funcionando porque ele usa a ação, não a frase) e se o motor com processamento de voz dispara troca de configuração em sequência logo ao ligar (o app aguenta 4 refeitos em 10 s e depois avisa "O áudio parou").

## Arquivos

- `/Volumes/Extreme SSD Breno/Projetos Beup/nexa-ios/Nexa/` (código Swift, Info.plist, ícone)
- `/Volumes/Extreme SSD Breno/Projetos Beup/nexa-ios/project.yml` (XcodeGen)
- `/Volumes/Extreme SSD Breno/Projetos Beup/nexa-ios/.github/workflows/build.yml`
- `/Volumes/Extreme SSD Breno/Projetos Beup/nexa-ios/compilar.sh`
- `/Volumes/Extreme SSD Breno/Projetos Beup/nexa-ios/README.md` (instalação, Atalho Vocal, Atalhos)
