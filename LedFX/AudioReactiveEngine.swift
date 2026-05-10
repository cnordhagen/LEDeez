import Accelerate
import AVFoundation
import Foundation
import QuartzCore

enum AudioReactiveEngineError: Error, LocalizedError {
    case invalidInputFormat
    case recordPermissionDenied

    var errorDescription: String? {
        switch self {
        case .invalidInputFormat:
            return "Could not read the microphone format. Try disconnecting Bluetooth audio or reconnecting your device."
        case .recordPermissionDenied:
            return "Microphone access was denied."
        }
    }
}

final class AudioReactiveEngine {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var fftSetup: FFTSetup?
    private let log2n: vDSP_Length = 10
    private var window: [Float] = []
    private var fftReal: [Float] = []
    private var fftImag: [Float] = []
    private var magnitudes: [Float] = []
    private var beatEnvelope: Float = 0
    private var lastBeatTime: CFTimeInterval = 0

    private var micTapInstalled = false
    private var mixerTapInstalled = false

    private(set) var inputMode: AudioInputMode = .microphone
    private var fileURL: URL?

    var onFeatures: ((AudioFeatures) -> Void)?

    init() {
        let n = 1 << Int(log2n)
        window = [Float](repeating: 0, count: n)
        vDSP_hann_window(&window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        fftReal = [Float](repeating: 0, count: n / 2)
        fftImag = [Float](repeating: 0, count: n / 2)
        magnitudes = [Float](repeating: 0, count: n / 2)
        fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))
    }

    deinit {
        if let fftSetup {
            vDSP_destroy_fftsetup(fftSetup)
        }
    }

    func setInputMode(_ mode: AudioInputMode, fileURL: URL? = nil) throws {
        stop()
        self.inputMode = mode
        self.fileURL = fileURL
        try configureSession()
        try attachNodes()
        try engine.start()
        if mode == .filePlayback, let url = fileURL {
            try scheduleFile(url)
            player.play()
        }
    }

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        try? session.setAllowHapticsAndSystemSoundsDuringRecording(false)
        switch inputMode {
        case .microphone:
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetoothHFP])
        case .filePlayback:
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try session.setActive(true, options: [])
    }

    private func removeMicTapIfNeeded() {
        guard micTapInstalled else { return }
        engine.inputNode.removeTap(onBus: 0)
        micTapInstalled = false
    }

    private func removeMixerTapIfNeeded() {
        guard mixerTapInstalled else { return }
        engine.mainMixerNode.removeTap(onBus: 0)
        mixerTapInstalled = false
    }

    private func attachNodes() throws {
        removeMicTapIfNeeded()
        removeMixerTapIfNeeded()

        engine.stop()
        engine.reset()
        engine.detach(player)

        let main = engine.mainMixerNode
        let bufferSize: AVAudioFrameCount = 1 << Int(log2n)

        switch inputMode {
        case .microphone:
            let input = engine.inputNode
            main.outputVolume = 0
            engine.connect(input, to: main, format: nil)
            engine.prepare()

            let tapFormat = input.outputFormat(forBus: 0)
            guard tapFormat.sampleRate > 0, tapFormat.channelCount > 0 else {
                throw AudioReactiveEngineError.invalidInputFormat
            }

            input.installTap(onBus: 0, bufferSize: bufferSize, format: tapFormat) { [weak self] buffer, _ in
                self?.process(buffer: buffer)
            }
            micTapInstalled = true

        case .filePlayback:
            engine.attach(player)
            engine.connect(player, to: main, format: nil)
            engine.prepare()

            let fmt = main.outputFormat(forBus: 0)
            guard fmt.sampleRate > 0, fmt.channelCount > 0 else {
                throw AudioReactiveEngineError.invalidInputFormat
            }

            main.installTap(onBus: 0, bufferSize: bufferSize, format: fmt) { [weak self] buffer, _ in
                self?.process(buffer: buffer)
            }
            mixerTapInstalled = true
        }
    }

    private func scheduleFile(_ url: URL) throws {
        let file = try AVAudioFile(forReading: url)
        player.stop()
        player.scheduleFile(file, at: nil, completionHandler: { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async {
                try? self.scheduleFile(url)
                self.player.play()
            }
        })
    }

    private func process(buffer: AVAudioPCMBuffer) {
        guard let fftSetup,
              let ch0 = buffer.floatChannelData?.pointee else { return }
        let frameCount = Int(buffer.frameLength)
        let n = 1 << Int(log2n)
        if frameCount < n { return }

        var mono = [Float](repeating: 0, count: n)
        if buffer.format.channelCount > 1, let ch1 = buffer.floatChannelData?[1] {
            vDSP_vadd(ch0, 1, ch1, 1, &mono, 1, vDSP_Length(n))
            var half: Float = 0.5
            vDSP_vsmul(mono, 1, &half, &mono, 1, vDSP_Length(n))
        } else {
            for i in 0..<n { mono[i] = ch0[i] }
        }

        vDSP_vmul(mono, 1, window, 1, &mono, 1, vDSP_Length(n))

        var split = DSPSplitComplex(realp: &fftReal, imagp: &fftImag)
        mono.withUnsafeBufferPointer { ptr in
            ptr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { complexPtr in
                vDSP_ctoz(complexPtr, 2, &split, 1, vDSP_Length(n / 2))
            }
        }
        vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

        let half = n / 2
        vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(half))
        var denom: Float = Float(half)
        vDSP_vsdiv(magnitudes, 1, &denom, &magnitudes, 1, vDSP_Length(half))
        vDSP_vsq(magnitudes, 1, &magnitudes, 1, vDSP_Length(half))
        for i in 0..<half {
            magnitudes[i] = sqrtf(max(0, magnitudes[i]))
        }

        let sr = Float(buffer.format.sampleRate)
        let binWidth = sr / Float(n)

        let bands = 48
        var downsampled = [Float](repeating: 0, count: bands)
        for b in 0..<bands {
            let start = (b * half) / bands
            let end = ((b + 1) * half) / bands
            var mx: Float = 0
            if start < end {
                vDSP_maxv(Array(magnitudes[start..<end]), 1, &mx, vDSP_Length(end - start))
            }
            downsampled[b] = min(1, mx * 8)
        }

        func binIndex(_ hz: Float) -> Int {
            min(max(0, Int((hz / binWidth).rounded(.down))), half - 1)
        }
        let bassEnd = binIndex(250)
        let midEnd = binIndex(2500)

        var bass: Float = 0
        if bassEnd > 0 {
            vDSP_maxv(magnitudes, 1, &bass, vDSP_Length(bassEnd))
        }
        var mid: Float = 0
        if midEnd > bassEnd {
            vDSP_maxv(Array(magnitudes[bassEnd..<midEnd]), 1, &mid, vDSP_Length(midEnd - bassEnd))
        }
        var treble: Float = 0
        if half > midEnd {
            vDSP_maxv(Array(magnitudes[midEnd..<half]), 1, &treble, vDSP_Length(half - midEnd))
        }

        bass = min(1, bass * 10)
        mid = min(1, mid * 10)
        treble = min(1, treble * 10)

        let sum = magnitudes.reduce(0, +)
        let overall = min(1, (sum / Float(half)) * 25)

        let now = CACurrentMediaTime()
        beatEnvelope = beatEnvelope * 0.92 + overall * 0.08
        var beat = false
        if overall > beatEnvelope * 1.35, overall > 0.08, now - lastBeatTime > 0.12 {
            beat = true
            lastBeatTime = now
        }

        let features = AudioFeatures(
            bass: bass,
            mid: mid,
            treble: treble,
            overall: overall,
            beat: beat,
            spectrum: downsampled
        )
        onFeatures?(features)
    }

    func stop() {
        removeMicTapIfNeeded()
        removeMixerTapIfNeeded()
        player.stop()
        engine.stop()
    }
}
