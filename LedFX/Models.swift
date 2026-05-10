import Foundation

enum AudioInputMode: String, CaseIterable, Identifiable {
    case microphone = "Microphone"
    case filePlayback = "File (in-app)"
    var id: String { rawValue }
}

enum TransportKind: String, CaseIterable, Identifiable {
    case wledHTTP = "WLED (HTTP)"
    case wledUDP = "WLED (UDP realtime)"
    case e131 = "E1.31 (sACN)"
    var id: String { rawValue }
}

enum LEDEffectKind: String, CaseIterable, Identifiable {
    case scroll = "Scroll"
    case spectrumBars = "Spectrum bars"
    case mirror = "Mirror"
    case beatPulse = "Beat pulse"
    case rainbowFlow = "Rainbow flow"
    case energy = "Energy (solid)"
    case wavelength = "Wavelength"
    case sparkle = "Sparkle"
    var id: String { rawValue }
}

struct EffectTuning: Sendable {
    var speed: Float = 1
    var intensity: Float = 1
}

struct RGB: Sendable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
}

struct AudioFeatures: Sendable {
    var bass: Float = 0
    var mid: Float = 0
    var treble: Float = 0
    var overall: Float = 0
    var beat: Bool = false
    var spectrum: [Float] = []
}

struct WLEDDiscoveredDevice: Identifiable, Hashable {
    var id: String { "\(name)-\(hostName)" }
    var name: String
    var hostName: String
    var ipv4: String?
}

enum PixelPostProcess {
    /// `saturation`: 1 = unchanged, 0 = grayscale, >1 more vivid (clamped).
    static func apply(brightness: Float, saturation: Float, pixels: [RGB]) -> [RGB] {
        let br = min(1, max(0, brightness))
        let sat = min(2, max(0, saturation))
        return pixels.map { p in
            var rf = Float(p.r) / 255
            var gf = Float(p.g) / 255
            var bf = Float(p.b) / 255
            let lum = 0.299 * rf + 0.587 * gf + 0.114 * bf
            rf = lum + (rf - lum) * sat
            gf = lum + (gf - lum) * sat
            bf = lum + (bf - lum) * sat
            rf *= br
            gf *= br
            bf *= br
            return RGB(
                r: UInt8(clamping: Int(rf * 255)),
                g: UInt8(clamping: Int(gf * 255)),
                b: UInt8(clamping: Int(bf * 255))
            )
        }
    }
}
