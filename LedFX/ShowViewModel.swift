import AVFoundation
import Foundation
import QuartzCore

@MainActor
@Observable
final class ShowViewModel {
    var audioInputMode: AudioInputMode = .microphone
    var transport: TransportKind = .wledHTTP
    var effectKind: LEDEffectKind = .scroll
    var effectTuning = EffectTuning()

    var ledCount: Int = 60 {
        didSet { renderer = LEDEffectRenderer(ledCount: ledCount, effect: effectKind) }
    }

    var targetHost: String = ""
    var wledHTTPPort: Int = 80
    var wledUDPPort: UInt16 = 21324
    var e131Port: UInt16 = 5568
    var e131Universe: UInt16 = 1
    var e131Multicast = false
    var wledGlobalBrightness: Int = 255

    var audioGain: Float = 1
    var audioSmoothing: Float = 0.35
    var silenceThreshold: Float = 0.02
    var masterBrightness: Float = 1
    var masterSaturation: Float = 1
    var outputRefreshHz: Double = 30
    var enableNetworkOutput = true

    var isRunning = false
    var lastError: String?
    var features = AudioFeatures()
    var previewPixels: [RGB] = []
    var discoveredDevices: [WLEDDiscoveredDevice] = []
    var audioFileURL: URL?

    private let audio = AudioReactiveEngine()
    private let wledHTTP = WLEDHTTPOutput()
    private let wledUDP = WLEDUDPRealtimeOutput()
    private let e131Out = E131Output()
    private let discovery = WLEDDiscovery()
    @ObservationIgnored
    private var renderer = LEDEffectRenderer(ledCount: 60, effect: .scroll)
    @ObservationIgnored
    private var smoothed = AudioFeatures()
    private var timer: Timer?
    private var lastTick: CFTimeInterval = 0

    init() {
        discovery.onUpdate = { [weak self] list in
            Task { @MainActor in
                self?.discoveredDevices = list
            }
        }
        audio.onFeatures = { [weak self] raw in
            Task { @MainActor in
                self?.integrateAudio(raw)
            }
        }
    }

    private func integrateAudio(_ raw: AudioFeatures) {
        let g = max(0.1, min(4, audioGain))
        let x = AudioFeatures(
            bass: min(1, raw.bass * g),
            mid: min(1, raw.mid * g),
            treble: min(1, raw.treble * g),
            overall: min(1, raw.overall * g),
            beat: raw.beat,
            spectrum: raw.spectrum.map { min(1, $0 * g) }
        )

        let a = min(0.95, max(0, audioSmoothing))
        smoothed.bass = smoothed.bass * a + x.bass * (1 - a)
        smoothed.mid = smoothed.mid * a + x.mid * (1 - a)
        smoothed.treble = smoothed.treble * a + x.treble * (1 - a)
        smoothed.overall = smoothed.overall * a + x.overall * (1 - a)
        smoothed.beat = x.beat

        if smoothed.spectrum.count != x.spectrum.count {
            smoothed.spectrum = x.spectrum
        } else {
            for i in x.spectrum.indices {
                smoothed.spectrum[i] = smoothed.spectrum[i] * a + x.spectrum[i] * (1 - a)
            }
        }

        var out = smoothed
        let th = silenceThreshold
        if out.overall < th {
            let gate = max(0, out.overall / max(0.004, th))
            out.bass *= gate
            out.mid *= gate
            out.treble *= gate
            out.overall *= gate
            for i in out.spectrum.indices {
                out.spectrum[i] *= gate
            }
        }

        features = out
    }

    func startDiscovery() {
        discovery.start()
    }

    func stopDiscovery() {
        discovery.stop()
    }

    func applyDiscovered(_ device: WLEDDiscoveredDevice) {
        targetHost = device.ipv4 ?? device.hostName
    }

    func startShow() {
        Task { await startShowAsync() }
    }

    private func startShowAsync() async {
        lastError = nil

        if audioInputMode == .microphone {
            let permitted = await Self.requestMicrophoneAccess()
            if !permitted {
                lastError =
                    "Microphone access denied. Enable it in Settings → Privacy & Security → Microphone, then try again."
                return
            }
        }

        renderer = LEDEffectRenderer(ledCount: ledCount, effect: effectKind)
        smoothed = AudioFeatures()

        do {
            switch audioInputMode {
            case .microphone:
                try audio.setInputMode(.microphone)
            case .filePlayback:
                guard let url = audioFileURL else {
                    lastError = "Choose an audio file first."
                    return
                }
                try audio.setInputMode(.filePlayback, fileURL: url)
            }
        } catch {
            lastError = error.localizedDescription
            return
        }

        wledUDP.reset()
        e131Out.reset()
        lastTick = CACurrentMediaTime()
        isRunning = true
        timer?.invalidate()

        let hz = max(10, min(60, outputRefreshHz))
        let interval = 1.0 / hz
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.tick()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopShow() {
        timer?.invalidate()
        timer = nil
        audio.stop()
        wledUDP.reset()
        e131Out.reset()
        isRunning = false
    }

    private static func requestMicrophoneAccess() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        case .undetermined:
            return await AVAudioApplication.requestRecordPermission()
        @unknown default:
            return false
        }
    }

    func tick() {
        guard isRunning else { return }
        let now = CACurrentMediaTime()
        let dt = Float(min(0.05, max(0.001, now - lastTick)))
        lastTick = now
        renderer.effect = effectKind
        let rawPixels = renderer.render(features: features, deltaTime: dt, tuning: effectTuning)
        let pixels = PixelPostProcess.apply(
            brightness: masterBrightness,
            saturation: masterSaturation,
            pixels: rawPixels
        )
        previewPixels = pixels

        guard enableNetworkOutput else { return }

        let host = targetHost.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }

        switch transport {
        case .wledHTTP:
            Task {
                do {
                    try await wledHTTP.send(
                        pixels: pixels,
                        host: host,
                        port: wledHTTPPort,
                        globalBrightness: wledGlobalBrightness
                    )
                } catch {
                    await MainActor.run { lastError = error.localizedDescription }
                }
            }
        case .wledUDP:
            wledUDP.send(pixels: pixels, host: host, port: wledUDPPort)
        case .e131:
            e131Out.send(
                pixels: pixels,
                host: host,
                port: e131Port,
                universe: e131Universe,
                useMulticast: e131Multicast
            )
        }
    }
}
