import AVFoundation

/// Áudio da conversa: um AVAudioEngine só, com o processamento de voz do iPhone ligado
/// (cancelamento de eco igual ao do FaceTime). A voz dela sai pelo mesmo motor, então o eco
/// dela não volta pro microfone e tu pode falar por cima pra interromper.
///
/// Entrada: microfone na taxa do aparelho -> mono -> PCM16 16 kHz em pedaços de 100 ms (3200 bytes).
/// Saída: PCM16 24 kHz da ponte -> fila no AVAudioPlayerNode, tocada em sequência.
final class AudioMotor {
    enum Falha: Error { case semEntrada, semConversor }
    enum Som { case ouvir }

    let medidor = Medidor()
    /// Pedaço de 100 ms pronto pra ponte. Chamado na thread de áudio.
    var aoCapturar: (@Sendable (Data) -> Void)?
    /// O áudio parou e não voltou (troca de rota ou interrupção que não deu pra retomar). Chamado na main.
    var aoFalhar: (@MainActor (String) -> Void)?

    private var engine = AVAudioEngine()
    private var voz = AVAudioPlayerNode()
    private var sfx = AVAudioPlayerNode()
    private let formatoVoz = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 24000, channels: 1, interleaved: false)!
    private let formato16k = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!

    // só a thread de áudio mexe nestes três depois de montado
    private var conversor: AVAudioConverter?
    private var formatoMono: AVAudioFormat?
    private var acumulado: [UInt8] = []

    private let trava = NSLock()
    private var geracao = 0
    private var pendentes = 0
    private(set) var ligado = false
    private var observadores: [NSObjectProtocol] = []
    private var refeitos: [TimeInterval] = []
    private var refazendo = false

    /// Tem voz dela na fila (tocando ou pra tocar).
    var tocando: Bool { trava.lock(); defer { trava.unlock() }; return pendentes > 0 }

    // MARK: ligar e desligar

    func iniciar() throws {
        guard !ligado else { return }
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
        try? s.setPreferredIOBufferDuration(0.02)
        try s.setActive(true)
        try montar()
        ligado = true
        observar()
    }

    func parar() {
        guard ligado else { return }
        ligado = false
        for o in observadores { NotificationCenter.default.removeObserver(o) }
        observadores = []
        pararFala()
        desmontar()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        medidor.mic = 0
        medidor.saida = 0
    }

    private func montar() throws {
        let e = AVAudioEngine()
        let entrada = e.inputNode
        // cancelamento de eco + supressão de ruído do próprio iOS (precisa ser antes de ler os formatos)
        try? entrada.setVoiceProcessingEnabled(true)

        let v = AVAudioPlayerNode(), f = AVAudioPlayerNode()
        e.attach(v)
        e.attach(f)
        e.connect(v, to: e.mainMixerNode, format: formatoVoz)
        e.connect(f, to: e.mainMixerNode, format: formatoVoz)

        let fmt = entrada.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else { throw Falha.semEntrada }
        guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: fmt.sampleRate, channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: mono, to: formato16k) else { throw Falha.semConversor }
        conversor = conv
        formatoMono = mono
        acumulado.removeAll(keepingCapacity: true)

        entrada.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] b, _ in self?.capturou(b) }
        e.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] b, _ in
            guard let self, let ch = b.floatChannelData else { return }
            self.medidor.saida = self.tocando ? Medidor.nivel(ch[0], Int(b.frameLength)) : 0
        }
        e.prepare()
        try e.start()
        engine = e
        voz = v
        sfx = f
    }

    private func desmontar() {
        engine.inputNode.removeTap(onBus: 0)
        engine.mainMixerNode.removeTap(onBus: 0)
        engine.stop()
    }

    // MARK: microfone

    private func capturou(_ b: AVAudioPCMBuffer) {
        guard let ch = b.floatChannelData, let mono = formatoMono, let conv = conversor else { return }
        let n = Int(b.frameLength)
        guard n > 0 else { return }
        medidor.mic = Medidor.nivel(ch[0], n)

        guard let m = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(n)), let dst = m.floatChannelData else { return }
        m.frameLength = AVAudioFrameCount(n)
        dst[0].update(from: ch[0], count: n)            // só o primeiro canal: mono

        let cap = AVAudioFrameCount(Double(n) * 16000 / mono.sampleRate) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: formato16k, frameCapacity: cap) else { return }
        var entregue = false
        var erro: NSError?
        conv.convert(to: out, error: &erro) { _, status in
            if entregue { status.pointee = .noDataNow; return nil }
            entregue = true
            status.pointee = .haveData
            return m
        }
        guard erro == nil, out.frameLength > 0, let i16 = out.int16ChannelData else { return }
        let bytes = Int(out.frameLength) * 2
        i16[0].withMemoryRebound(to: UInt8.self, capacity: bytes) { p in
            acumulado.append(contentsOf: UnsafeBufferPointer(start: p, count: bytes))
        }
        while acumulado.count >= 3200 {
            let pedaco = Data(acumulado[0..<3200])
            acumulado.removeFirst(3200)
            aoCapturar?(pedaco)
        }
    }

    // MARK: voz dela

    /// PCM16 mono 24 kHz, little endian. Entra no fim da fila.
    func tocar(_ pcm: Data) {
        guard ligado, engine.isRunning else { return }
        let n = pcm.count / 2
        guard n > 0, let buf = AVAudioPCMBuffer(pcmFormat: formatoVoz, frameCapacity: AVAudioFrameCount(n)),
              let dst = buf.floatChannelData?[0] else { return }
        buf.frameLength = AVAudioFrameCount(n)
        pcm.withUnsafeBytes { raw in
            for i in 0..<n {
                dst[i] = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))) / 32768
            }
        }
        trava.lock()
        let g = geracao
        pendentes += 1
        trava.unlock()
        voz.scheduleBuffer(buf, completionCallbackType: .dataPlayedBack) { [weak self] _ in self?.tocou(g) }
        if !voz.isPlaying { voz.play() }
    }

    private func tocou(_ g: Int) {
        trava.lock()
        if g == geracao { pendentes = max(0, pendentes - 1) }
        trava.unlock()
    }

    /// Para a voz dela na hora e joga fora o que estava na fila.
    func pararFala() {
        trava.lock()
        geracao += 1
        pendentes = 0
        trava.unlock()
        voz.stop()
        voz.volume = 1
        medidor.saida = 0
    }

    /// Abaixa a voz dela enquanto tu fala por cima (volta sozinha se a ponte não interromper).
    func abaixar(_ sim: Bool) { voz.volume = sim ? 0.25 : 1 }

    func som(_ s: Som) {
        guard ligado, engine.isRunning else { return }
        let b: AVAudioPCMBuffer
        switch s { case .ouvir: b = somOuvir }
        sfx.scheduleBuffer(b, completionHandler: nil)
        if !sfx.isPlaying { sfx.play() }
    }

    private lazy var somOuvir: AVAudioPCMBuffer = tom([(740, 0.075), (1110, 0.16)], volume: 0.11)

    private func tom(_ notas: [(Double, Double)], volume: Float) -> AVAudioPCMBuffer {
        let sr = formatoVoz.sampleRate
        let total = notas.reduce(0) { $0 + Int($1.1 * sr) }
        let b = AVAudioPCMBuffer(pcmFormat: formatoVoz, frameCapacity: AVAudioFrameCount(total))!
        b.frameLength = AVAudioFrameCount(total)
        let p = b.floatChannelData![0]
        var i = 0
        for (freq, dur) in notas {
            let m = Int(dur * sr)
            for k in 0..<m {
                let t = Double(k) / sr
                let env = max(0, min(min(1, t / 0.006), min(1, (dur - t) / (dur * 0.7))))
                let onda = sin(2 * .pi * freq * t) + 0.18 * sin(4 * .pi * freq * t)
                p[i] = volume * Float(env * onda)
                i += 1
            }
        }
        return b
    }

    // MARK: rota, interrupção e reinício

    private func observar() {
        let nc = NotificationCenter.default
        observadores.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: nil, queue: .main) { [weak self] n in
            guard let self, self.ligado, (n.object as AnyObject?) === self.engine else { return }
            self.agendarRefazer()
        })
        observadores.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, self.ligado,
                  let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let tipo = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            if tipo == .began {
                self.pararFala()
            } else {
                try? AVAudioSession.sharedInstance().setActive(true)
                self.agendarRefazer()
            }
        })
        observadores.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.ligado else { return }
            try? AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth])
            try? AVAudioSession.sharedInstance().setActive(true)
            self.agendarRefazer()
        })
    }

    /// Junta várias notificações seguidas (fone entrando dispara mais de uma) num reinício só.
    private func agendarRefazer() {
        guard !refazendo else { return }
        refazendo = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            self.refazendo = false
            guard self.ligado else { return }
            let agora = ProcessInfo.processInfo.systemUptime
            self.refeitos = self.refeitos.filter { agora - $0 < 10 } + [agora]
            self.pararFala()
            self.desmontar()
            do {
                if self.refeitos.count > 4 { throw Falha.semEntrada }
                try self.montar()
            } catch {
                MainActor.assumeIsolated { self.aoFalhar?("O áudio parou. Toque pra conversar de novo.") }
            }
        }
    }
}
