import Foundation

struct LEDEffectRenderer: Sendable {
    var ledCount: Int
    var effect: LEDEffectKind
    private var scrollPhase: Float = 0
    private var rainbowPhase: Float = 0
    private var lastBeatFlash: Float = 0
    private var wavePhase: Float = 0
    private var rngState: UInt64 = 0x9e37_79b9_7f4a_7c15
    private var sparkleHeat: [Float] = []

    init(ledCount: Int, effect: LEDEffectKind) {
        self.ledCount = ledCount
        self.effect = effect
    }

    mutating func render(features: AudioFeatures, deltaTime: Float, tuning: EffectTuning) -> [RGB] {
        var pixels = [RGB](repeating: RGB(r: 0, g: 0, b: 0), count: ledCount)
        let n = max(ledCount, 1)
        let spec = features.spectrum
        let sp = max(0.25, tuning.speed)
        let inten = min(2, max(0.1, tuning.intensity))
        let bass = smooth(features.bass)
        let mid = smooth(features.mid)
        let treble = smooth(features.treble)
        let energy = smooth(features.overall)

        switch effect {
        case .scroll:
            scrollPhase += deltaTime * sp * (0.35 + bass * 2.5)
            let hue = scrollPhase.truncatingRemainder(dividingBy: 1)
            let head = Int(scrollPhase * Float(n)) % n
            for i in 0..<n {
                let dist = min(abs(i - head), abs(i - head + n), abs(i - head - n))
                let falloff = max(0, 1 - Float(dist) / Float(max(n / 4, 1)))
                let v = Double(falloff) * Double(0.2 + energy) * Double(inten)
                let (r, g, b) = hsvToRGB(h: hue + Float(i) * 0.02, s: 0.85, v: v)
                pixels[i] = RGB(r: r, g: g, b: b)
            }

        case .spectrumBars:
            let bins = max(spec.count, 8)
            for i in 0..<n {
                let t = Float(i) / Float(max(n - 1, 1))
                let idx = min(bins - 1, Int(t * Float(bins)))
                let mag = spec.indices.contains(idx) ? spec[idx] : 0
                let h = t * 0.85 + bass * 0.15
                let (r, g, b) = hsvToRGB(h: h, s: 0.9, v: Double(mag) * Double(inten))
                pixels[i] = RGB(r: r, g: g, b: b)
            }

        case .mirror:
            let half = n / 2
            for i in 0..<half {
                let t = Float(i) / Float(max(half - 1, 1))
                let idx = min(max(spec.count - 1, 0), Int(t * Float(spec.count)))
                let mag = spec.indices.contains(idx) ? spec[idx] : energy
                let h = treble * 0.3 + t * 0.5
                let (r, g, b) = hsvToRGB(h: h, s: 0.75, v: Double(mag) * Double(inten))
                pixels[i] = RGB(r: r, g: g, b: b)
                let j = n - 1 - i
                if j != i { pixels[j] = pixels[i] }
            }
            if n % 2 == 1 {
                let (r, g, b) = hsvToRGB(h: mid, s: 0.8, v: Double(energy) * Double(inten))
                pixels[half] = RGB(r: r, g: g, b: b)
            }

        case .beatPulse:
            if features.beat {
                lastBeatFlash = 1
            }
            lastBeatFlash = max(0, lastBeatFlash - deltaTime * 2.2 * sp)
            let pulse = max(Double(energy), Double(lastBeatFlash)) * Double(inten)
            let h = Double(bass * 0.25 + mid * 0.15)
            for i in 0..<n {
                let (r, g, b) = hsvToRGB(h: Float(h) + Float(i) / Float(n) * 0.08, s: 0.65, v: pulse)
                pixels[i] = RGB(r: r, g: g, b: b)
            }

        case .rainbowFlow:
            rainbowPhase += deltaTime * sp * (0.12 + treble * 0.8)
            for i in 0..<n {
                let h = rainbowPhase + Float(i) / Float(n)
                let v = (0.15 + Double(energy) * 0.85) * Double(inten)
                let (r, g, b) = hsvToRGB(h: h.truncatingRemainder(dividingBy: 1), s: 0.95, v: v)
                pixels[i] = RGB(r: r, g: g, b: b)
            }

        case .energy:
            let h = bass * 0.35 + mid * 0.2 + treble * 0.15
            let v = Double(energy) * Double(inten)
            let (r, g, b) = hsvToRGB(h: h, s: 0.9, v: min(1, v))
            for i in 0..<n {
                pixels[i] = RGB(r: r, g: g, b: b)
            }

        case .wavelength:
            wavePhase += deltaTime * sp * (1.2 + energy * 3)
            let bins = max(spec.count, 4)
            for i in 0..<n {
                let t = Float(i) / Float(max(n - 1, 1))
                let idx = min(bins - 1, Int(t * Float(bins)))
                let mag = spec.indices.contains(idx) ? spec[idx] : energy
                let phase = t * Float.pi * 4 * sp + wavePhase
                let w = (sin(phase) * 0.5 + 0.5) * mag
                let h = t * 0.9 + bass * 0.1
                let (r, g, b) = hsvToRGB(h: h, s: 0.85, v: Double(w) * Double(inten))
                pixels[i] = RGB(r: r, g: g, b: b)
            }

        case .sparkle:
            if sparkleHeat.count != n {
                sparkleHeat = [Float](repeating: 0, count: n)
            }
            for i in 0..<n {
                sparkleHeat[i] *= 0.9 - (1 - sp) * 0.02
            }
            if features.beat {
                let sparks = max(1, n / 10)
                for _ in 0..<sparks {
                    let idx = Int(nextRandom() % UInt32(max(1, n)))
                    sparkleHeat[idx] = min(1, sparkleHeat[idx] + 0.65 * inten)
                }
            }
            let base = energy * 0.12 * inten
            for i in 0..<n {
                let h = Float(i) / Float(max(n - 1, 1)) * 0.75 + bass * 0.2
                let v = Double(max(sparkleHeat[i], base))
                let (r, g, b) = hsvToRGB(h: h, s: 0.55 + treble * 0.2, v: min(1, v))
                pixels[i] = RGB(r: r, g: g, b: b)
            }
        }

        return pixels
    }

    private mutating func nextRandom() -> UInt32 {
        rngState = rngState &* 6364136223846793005 &+ 1442695040888963407
        return UInt32(truncatingIfNeeded: rngState >> 32)
    }

    private func smooth(_ x: Float) -> Float {
        min(1, max(0, x))
    }

    private func hsvToRGB(h: Float, s: Float, v: Double) -> (UInt8, UInt8, UInt8) {
        let hh = Double(h.truncatingRemainder(dividingBy: 1))
        let ss = Double(s)
        let vv = min(1, max(0, v))
        let i = Int(hh * 6)
        let f = hh * 6 - Double(i)
        let p = vv * (1 - ss)
        let q = vv * (1 - f * ss)
        let t = vv * (1 - (1 - f) * ss)
        let (r, g, b): (Double, Double, Double)
        switch i % 6 {
        case 0: (r, g, b) = (vv, t, p)
        case 1: (r, g, b) = (q, vv, p)
        case 2: (r, g, b) = (p, vv, t)
        case 3: (r, g, b) = (p, q, vv)
        case 4: (r, g, b) = (t, p, vv)
        default: (r, g, b) = (vv, p, q)
        }
        return (UInt8(clamping: Int(r * 255)), UInt8(clamping: Int(g * 255)), UInt8(clamping: Int(b * 255)))
    }
}
