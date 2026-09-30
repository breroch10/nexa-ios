# Nexa para iPhone

App nativo da Nexa. Conversa por voz com a mesma ponte da v2 (VPS, pela Tailscale), acorda com a palavra "Nexa" sem tocar na tela, continua com o iPhone bloqueado e roda os teus Atalhos quando a Nexa pede.

- Esfera no centro: toque liga e desliga a conversa.
- Teal fino = ouvindo. Laranja forte = falando. Arco girando = conectando ou pensando.
- Fale por cima dela para interromper (o iPhone cancela o eco da voz dela, igual ao FaceTime).
- Botão "Tela completa" abre a v2 (telas, chat, reels) por cima do app.

Precisa: iPhone com iOS 17 ou mais novo, app Tailscale ligado e logado na tua conta.

---

## 1. Instalar pelo Sideloadly (Mac + cabo)

O arquivo é `build/Nexa.ipa` (sai do GitHub Actions sem assinatura; o Sideloadly assina com o teu Apple ID).

1. Baixe o Sideloadly em sideloadly.io e abra no Mac.
2. Ligue o iPhone no cabo. Se o iPhone perguntar "Confiar neste computador?", toque em Confiar e digite o código.
3. No Sideloadly: arraste o `Nexa.ipa` para a janela, confira que o teu iPhone aparece em "iDevice", digite o teu Apple ID em "Apple Account" e clique em **Start**.
4. O Sideloadly pede a senha do Apple ID e o código de dois fatores. Digite você mesmo, direto no Sideloadly.
5. Espere aparecer "Done". O ícone da Nexa aparece na tela do iPhone.

### Modo de Desenvolvedor (só na primeira vez)

1. No iPhone: **Ajustes > Privacidade e Segurança > Modo de Desenvolvedor** (a opção aparece depois que o primeiro app é instalado pelo Sideloadly).
2. Ligue, toque em Reiniciar.
3. Depois que o iPhone voltar, desbloqueie e toque em **Ativar** no aviso.

### Confiar no desenvolvedor (só na primeira vez)

1. **Ajustes > Geral > VPN e Gerenciamento de Dispositivos**.
2. Toque no teu Apple ID (em "App de Desenvolvedor").
3. Toque em **Confiar** e confirme.

### Primeira abertura

1. Ligue a Tailscale no iPhone.
2. Abra a Nexa, toque na esfera e permita o microfone.
3. Ouviu o toque curto de "pronto"? Pode falar.

### Reinstalar a cada 7 dias

Com Apple ID grátis a assinatura vale 7 dias. Depois disso o app não abre mais.
Para renovar: cabo no Mac, Sideloadly, mesmo `Nexa.ipa`, Start (não perde nada).
Dica: no Sideloadly, deixe marcado "Automatic refresh" (o Mac precisa estar ligado, com o Sideloadly aberto e o iPhone na mesma rede Wi-Fi).

---

## 2. Acordar só com a voz: "Nexa"

O app entrega para o iOS a ação **Conversar com a Nexa** (abre o app e já começa a ouvir). O iOS escuta a palavra, não o app: bateria e privacidade ficam com o sistema.

### Atalho Vocal (sem "E aí Siri", iOS 18 ou mais novo)

1. **Ajustes > Acessibilidade > Atalhos Vocais** (em algumas versões aparece como Atalhos de Voz).
2. Toque em **Configurar** (ou **Adicionar Ação**).
3. Escolha **Conversar com a Nexa** (fica na lista de atalhos, na parte dos apps, em "Nexa").
4. Na hora de escolher a frase, fale **"Nexa"** três vezes, como o iPhone pedir.
5. Pronto: fale "Nexa" com o iPhone por perto.

Com o iPhone bloqueado: você fala "Nexa", o iPhone pede o Face ID, desbloqueia e a Nexa abre já ouvindo.

### Outros jeitos de chamar

- **"E aí Siri, Nexa"** ou **"E aí Siri, falar com a Nexa"**.
- **Toque Traseiro**: Ajustes > Acessibilidade > Toque > Toque Traseiro > Toque Duplo > Conversar com a Nexa.
- **Link**: `nexa://ouvir` abre e liga; `nexa://encerrar` desliga; `nexa://tela` abre a tela completa.
- **Encerrar pela voz**: "E aí Siri, encerrar a Nexa".

---

## 3. Segundo plano

- Com a conversa ligada, pode bloquear o iPhone ou ir para outro app: ela continua ouvindo e falando (aparece a bolinha laranja do microfone no topo).
- Tocar na esfera encerra e **desliga o microfone**. Nada fica ouvindo depois disso.
- Se ninguém falar por 15 minutos, ela encerra sozinha.
- Ligação, Siri ou troca de fone pausam o áudio e ele volta sozinho quando dá.
- Se a rede cair no meio (Wi-Fi para 4G), o app reconecta sozinho até 3 vezes por minuto.

---

## 4. A Nexa mexendo no iPhone (Atalhos)

Quando a ponte manda

```json
{"tipo": "iphone", "acao": "atalho", "nome": "Nexa Lembrete", "entrada": "ligar pro contador amanhã 9h"}
```

o app roda o Atalho do app Atalhos com esse nome, passando a entrada como texto, e volta para a Nexa no fim
(`shortcuts://x-callback-url/run-shortcut?name=...&input=text&text=...&x-success=nexa://voltar`).

Quando a ponte manda `{"tipo": "iphone", "acao": "abrir", "url": "..."}`, o app abre a URL (site, WhatsApp, Maps, qualquer app com link).

Com isso a Nexa alcança tudo que o app Atalhos alcança: alarme, timer, lembrete, agenda, mensagem, ligação, Casa, música, fotos, localização, modo de foco, lanterna, volume, e qualquer app que tenha ações no Atalhos.

### Como preparar

1. Abra o app **Atalhos** e crie um atalho para cada coisa. Use nomes que começam com "Nexa", por exemplo:
   - **Nexa Lembrete**: "Adicionar Novo Lembrete" com o texto = Entrada do Atalho.
   - **Nexa Alarme**: "Criar Alarme" com a hora vinda da Entrada do Atalho.
   - **Nexa Mensagem**: "Enviar Mensagem" com o texto = Entrada do Atalho.
   - **Nexa Música**: "Tocar Música" ou "Pesquisar no Spotify" com a Entrada.
   - **Nexa Casa**: cenas do app Casa.
   - **Nexa Onde Estou**: "Obter Localização Atual".
2. Rode cada atalho uma vez na mão para aceitar as permissões que o Atalhos pedir.
3. Se o iPhone estiver bloqueado quando o pedido chegar, o app avisa "Desbloqueie o iPhone" e roda assim que você desbloquear.

Observação: a ponte ainda não tem a ferramenta que manda `tipo: "iphone"`. O app já entende a mensagem; falta a ponte ganhar essa ferramenta (ver RELATORIO.md).

---

## 5. Compilar de novo (sem Xcode no Mac)

O GitHub Actions compila na nuvem (runner macos-15 com Xcode) a cada push em `main` que mexa em `Nexa/`, `project.yml` ou no workflow.

```bash
cd "/Volumes/Extreme SSD Breno/Projetos Beup/nexa-ios"
git push                                  # dispara o build
gh run watch                              # acompanha
gh run download -n Nexa -D build          # baixa build/Nexa.ipa
```

Para rodar na mão: `gh workflow run build.yml`. O projeto Xcode não fica no repositório: o XcodeGen gera a partir do `project.yml`.
Minutos de macOS no plano grátis são limitados: não rode build à toa.

## Código

| Arquivo | O que faz |
|---|---|
| `Nexa/Conversa.swift` | Estado da conversa, mensagens da ponte, reconexão, ações do iPhone |
| `Nexa/AudioMotor.swift` | AVAudioSession `.voiceChat`, microfone para 16 kHz, voz dela a 24 kHz em fila |
| `Nexa/Ponte.swift` | WebSocket `wss://beup-vps.tail76dcad.ts.net:8444/ws?aparelho=iphone-app` com Origin |
| `Nexa/Intents.swift` | "Conversar com a Nexa" e "Encerrar a conversa com a Nexa" (Siri, Atalhos, Atalhos Vocais) |
| `Nexa/Esfera.swift` | A esfera em SwiftUI (Canvas) que pulsa com o áudio |
| `Nexa/TelaPrincipal.swift` | Tela: NEXA, esfera, estado, legenda, botões |
| `Nexa/Navegador.swift` | Tela completa (v2) num Safari por cima do app |
