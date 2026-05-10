//
//  ContentView.swift
//  LedFX
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var viewModel: ShowViewModel
    @State private var fileImporterOpen = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    previewStrip

                    controlsCard(title: "Audio") {
                        Picker("Source", selection: $viewModel.audioInputMode) {
                            ForEach(AudioInputMode.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)

                        if viewModel.audioInputMode == .filePlayback {
                            Button {
                                fileImporterOpen = true
                            } label: {
                                Label(
                                    viewModel.audioFileURL?.lastPathComponent ?? "Choose audio file…",
                                    systemImage: "doc.badge.plus"
                                )
                            }
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("Input gain")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $viewModel.audioGain, in: 0.25...3, step: 0.05)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Temporal smoothing (LedFX-style blur)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $viewModel.audioSmoothing, in: 0...0.92, step: 0.02)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Silence gate (reduce flicker when quiet)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $viewModel.silenceThreshold, in: 0...0.15, step: 0.005)
                        }

                        Text(
                            "iOS cannot capture other apps’ audio like desktop loopback. Use the microphone, or pick a file to play and analyze inside LedFX."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    controlsCard(title: "Effect") {
                        Picker("Effect", selection: $viewModel.effectKind) {
                            ForEach(LEDEffectKind.allCases) { e in
                                Text(e.rawValue).tag(e)
                            }
                        }
                        HStack {
                            Text("LED count")
                            Spacer()
                            TextField("60", value: $viewModel.ledCount, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 80)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Speed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $viewModel.effectTuning.speed, in: 0.25...2.5, step: 0.05)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Intensity")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $viewModel.effectTuning.intensity, in: 0.25...2, step: 0.05)
                        }
                    }

                    controlsCard(title: "Color & levels") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Master brightness (after effect)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $viewModel.masterBrightness, in: 0.05...1, step: 0.01)
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Saturation")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $viewModel.masterSaturation, in: 0...2, step: 0.02)
                        }
                    }

                    controlsCard(title: "Output") {
                        Toggle("Send to network devices", isOn: $viewModel.enableNetworkOutput)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Refresh rate (Hz)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Picker("Hz", selection: $viewModel.outputRefreshHz) {
                                Text("15").tag(15.0)
                                Text("20").tag(20.0)
                                Text("30").tag(30.0)
                                Text("45").tag(45.0)
                                Text("60").tag(60.0)
                            }
                            .pickerStyle(.segmented)
                        }

                        Picker("Transport", selection: $viewModel.transport) {
                            ForEach(TransportKind.allCases) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }

                        HStack {
                            Text("Device address")
                            Spacer()
                            TextField("192.168.1.50", text: $viewModel.targetHost)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .multilineTextAlignment(.trailing)
                        }

                        if viewModel.transport == .wledHTTP {
                            HStack {
                                Text("HTTP port")
                                Spacer()
                                TextField("80", value: $viewModel.wledHTTPPort, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 80)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("WLED master brightness (bri, 1–255)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Slider(
                                    value: Binding(
                                        get: { Double(viewModel.wledGlobalBrightness) },
                                        set: { viewModel.wledGlobalBrightness = Int($0.rounded()) }
                                    ),
                                    in: 1...255,
                                    step: 1
                                )
                            }
                        }

                        if viewModel.transport == .wledUDP {
                            HStack {
                                Text("UDP port")
                                Spacer()
                                TextField("21324", value: $viewModel.wledUDPPort, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 80)
                            }
                            Text("Use the “Realtime” / UDP port from WLED → Config → Sync interfaces.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if viewModel.transport == .e131 {
                            HStack {
                                Text("Universe")
                                Spacer()
                                TextField("1", value: $viewModel.e131Universe, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 80)
                            }
                            HStack {
                                Text("sACN port")
                                Spacer()
                                TextField("5568", value: $viewModel.e131Port, format: .number)
                                    .keyboardType(.numberPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: 80)
                            }
                            Toggle("Multicast (239.255.*.*)", isOn: $viewModel.e131Multicast)
                            Text("Uncheck multicast to send directly to the controller IP.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    controlsCard(title: "WLED on network") {
                        HStack {
                            Button("Scan") { viewModel.startDiscovery() }
                            Button("Stop scan") { viewModel.stopDiscovery() }
                        }
                        .buttonStyle(.bordered)

                        ForEach(viewModel.discoveredDevices) { d in
                            Button {
                                viewModel.applyDiscovered(d)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name).font(.headline)
                                    Text(d.ipv4 ?? d.hostName).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if let err = viewModel.lastError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding()
            }
            .background(Color(red: 0.06, green: 0.05, blue: 0.12))
            .navigationTitle("LedFX")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if viewModel.isRunning {
                        Button("Stop") { viewModel.stopShow() }
                            .tint(.red)
                    } else {
                        Button("Start") { viewModel.startShow() }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Color(red: 0.55, green: 0.35, blue: 0.95))
        .fileImporter(
            isPresented: $fileImporterOpen,
            allowedContentTypes: [.audio, .mp3, .mpeg4Audio, .wav],
            allowsMultipleSelection: false
        ) { result in
            if case let .success(urls) = result, let u = urls.first {
                _ = u.startAccessingSecurityScopedResource()
                viewModel.audioFileURL = u
            }
        }
    }

    private var previewStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preview")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            GeometryReader { geo in
                let w = geo.size.width
                let n = max(viewModel.previewPixels.count, 1)
                let cell = w / CGFloat(n)
                HStack(spacing: 0) {
                    ForEach(0..<viewModel.previewPixels.count, id: \.self) { i in
                        let p = viewModel.previewPixels[i]
                        Rectangle()
                            .fill(Color(red: Double(p.r) / 255, green: Double(p.g) / 255, blue: Double(p.b) / 255))
                            .frame(width: max(1, cell))
                    }
                }
            }
            .frame(height: 36)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 12) {
                meter("Bass", viewModel.features.bass)
                meter("Mid", viewModel.features.mid)
                meter("Treble", viewModel.features.treble)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func meter(_ title: String, _ v: Float) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(Color(red: 0.55, green: 0.35, blue: 0.95))
                        .frame(width: g.size.width * CGFloat(min(1, v)))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity)
    }

    private func controlsCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding()
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

#Preview {
    ContentView(viewModel: ShowViewModel())
}
