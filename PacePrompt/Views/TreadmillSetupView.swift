import SwiftUI
import UIKit

struct TreadmillSetupView: View {
    @ObservedObject var treadmill: TreadmillSetupViewModel
    @State private var copiedDiagnostics = false
#if DEBUG
    @State private var deckAndBeltConfirmed = false
    @State private var consoleAndSafetyKeyConfirmed = false
    @State private var noOtherControllerConfirmed = false
    @State private var showingRequestControlConfirmation = false
#endif

    var body: some View {
        List {
            statusSection
            discoverySection

            if treadmill.canDisconnect {
                connectionSection
            }

            capabilitySection
            subscriptionSection
#if DEBUG
            requestControlDiagnosticSection
#endif
            diagnosticSection

            if !treadmill.characteristics.isEmpty {
                characteristicSection
            }

            safetySection
        }
        .navigationTitle("Treadmill")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusSection: some View {
        Section {
            StatusRow(
                title: "Bluetooth",
                value: treadmill.availability.title,
                symbol: treadmill.availability.isAvailable
                    ? "checkmark.circle.fill"
                    : "exclamationmark.circle.fill",
                colour: treadmill.availability.isAvailable ? .green : .orange
            )
            StatusRow(
                title: "Connection",
                value: treadmill.connectionState.title,
                symbol: treadmill.canDisconnect ? "link.circle.fill" : "link.badge.plus",
                colour: treadmill.canDisconnect ? .green : .secondary
            )
            if let error = treadmill.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Status")
        } footer: {
            if treadmill.availability == .unauthorized {
                Text("Bluetooth permission has not been granted. You can review PacePrompt in the iPhone Settings app.")
            } else if treadmill.availability == .poweredOff {
                Text("Turn on Bluetooth before scanning.")
            }
        }
    }

    private var discoverySection: some View {
        Section {
            Button {
                treadmill.toggleScan()
            } label: {
                Label(
                    treadmill.isScanning ? "Stop scanning" : "Scan for FTMS treadmills",
                    systemImage: treadmill.isScanning ? "stop.circle" : "dot.radiowaves.left.and.right"
                )
            }
            .disabled(!treadmill.canScan && !treadmill.isScanning)

            if treadmill.isScanning && treadmill.devices.isEmpty {
                HStack {
                    ProgressView()
                    Text("Looking for Fitness Machine Service 0x1826")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(treadmill.devices) { device in
                Button {
                    treadmill.connect(to: device)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(device.name)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text("\(device.rssi) dBm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(device.id.uuidString)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
        } header: {
            Text("Discovery")
        } footer: {
            Text("Scanning starts only when you press the button and is restricted to devices advertising FTMS.")
        }
    }

    private var connectionSection: some View {
        Section {
            Button("Disconnect", role: .destructive) {
                treadmill.disconnect()
            }
        }
    }

    private var capabilitySection: some View {
        Section("Capabilities") {
            CapabilityCard(
                title: "Fitness Machine Feature · 0x2ACC",
                decoded: "Speed target: \(treadmill.speedTargetSettingText)\nInclination target: \(treadmill.inclinationTargetSettingText)",
                raw: treadmill.featureFlags.rawHex,
                issue: treadmill.featureFlags.issue
            )
            CapabilityCard(
                title: "Supported Speed Range · 0x2AD4",
                decoded: treadmill.speedRangeText,
                raw: treadmill.speedRange.rawHex,
                issue: treadmill.speedRange.issue
            )
            CapabilityCard(
                title: "Supported Inclination Range · 0x2AD5",
                decoded: treadmill.inclinationRangeText,
                raw: treadmill.inclinationRange.rawHex,
                issue: treadmill.inclinationRange.issue
            )
        }
    }

    private var subscriptionSection: some View {
        Section {
            ForEach(treadmill.subscriptions) { subscription in
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(FTMSUUID.name(for: subscription.uuid)) · 0x\(subscription.uuid)")
                        Spacer()
                        Text(subscription.state.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(subscriptionColour(subscription.state))
                    }
                    if let detail = subscription.state.detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    let packetCount = treadmill.diagnostics.count { $0.uuid == subscription.uuid }
                    Text(packetCount == 0 ? "No packets received" : "\(packetCount) packet\(packetCount == 1 ? "" : "s") captured")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Passive subscriptions")
        } footer: {
            Text("Subscribed means CoreBluetooth enabled notifications. No packets received is not a zero measurement or proof that the treadmill lacks data.")
        }
    }

    private var diagnosticSection: some View {
        Section {
            if treadmill.diagnostics.isEmpty {
                ContentUnavailableView(
                    "No packets received",
                    systemImage: "waveform.path.ecg.rectangle",
                    description: Text("Telemetry remains unavailable until an initial read or notification returns a value.")
                )
            } else {
                ForEach(treadmill.diagnostics.reversed()) { diagnostic in
                    DiagnosticPacketCard(diagnostic: diagnostic)
                }
            }

            ShareLink(item: treadmill.diagnosticReport) {
                Label("Share diagnostics", systemImage: "square.and.arrow.up")
            }

            Button {
                UIPasteboard.general.string = treadmill.diagnosticReport
                copiedDiagnostics = true
            } label: {
                Label(copiedDiagnostics ? "Diagnostics copied" : "Copy diagnostics", systemImage: "doc.on.doc")
            }

            if !treadmill.diagnostics.isEmpty {
                Button("Clear packet log", role: .destructive) {
                    treadmill.clearDiagnostics()
                    copiedDiagnostics = false
                }
            }
        } header: {
            Text("In-memory packet log · \(treadmill.diagnostics.count)/\(treadmill.diagnosticCapacity)")
        } footer: {
            Text("Packets are timestamped and held only in memory. Copy and share happen only when you choose them; PacePrompt does not persist or transmit diagnostics automatically.")
        }
    }

#if DEBUG
    private var requestControlDiagnosticSection: some View {
        Section {
            LabeledContent("Diagnostic state", value: treadmill.requestControlReadiness.title)
            if let detail = treadmill.requestControlReadiness.detail {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Toggle("Deck clear and belt stationary", isOn: $deckAndBeltConfirmed)
            Toggle("Console and safety key within reach", isOn: $consoleAndSafetyKeyConfirmed)
            Toggle("No other app or person controlling", isOn: $noOtherControllerConfirmed)

            Button(role: .destructive) {
                showingRequestControlConfirmation = true
            } label: {
                Label("Send one Request Control · 00", systemImage: "lock.open.trianglebadge.exclamationmark")
            }
            .disabled(!requestControlSubmissionEnabled)
            .confirmationDialog(
                "Send exactly one Request Control write?",
                isPresented: $showingRequestControlConfirmation,
                titleVisibility: .visible
            ) {
                Button("Send 00 once", role: .destructive) {
                    treadmill.submitRequestControlDiagnosticOnce()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This consumes the installed diagnostic build's one-write allowance. It cannot retry, reconnect, or send any other Control Point opcode.")
            }

            if !treadmill.requestControlDiagnostics.isEmpty {
                ForEach(treadmill.requestControlDiagnostics.reversed()) { record in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.event.reportLine)
                            .font(.caption)
                        Text(record.timestamp, format: .dateTime.hour().minute().second())
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Issue #51 · Debug-only Request Control proof")
        } footer: {
            Text("Only the exact single byte 00 is allow-listed. Any error or uncertainty ends the proof; use Disconnect and send no compensating command.")
        }
    }

    private var requestControlSubmissionEnabled: Bool {
        treadmill.requestControlReadiness.permitsRequest
            && deckAndBeltConfirmed
            && consoleAndSafetyKeyConfirmed
            && noOtherControllerConfirmed
    }
#endif

    private var characteristicSection: some View {
        Section("Discovered characteristics") {
            ForEach(treadmill.characteristics) { characteristic in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(FTMSUUID.name(for: characteristic.uuid)) · 0x\(characteristic.uuid)")
                    Text(characteristic.properties.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var safetySection: some View {
        Section {
#if DEBUG
            Label("Issue #51 one-write diagnostic", systemImage: "lock.shield")
#else
            Label("Read-only capability check", systemImage: "lock.shield")
#endif
        } footer: {
#if DEBUG
            Text("The Debug-only diagnostic can submit Request Control 00 once. It cannot send speed, inclination, Start, Stop/Pause, Reset, retry, reconnect or workout commands. The physical console and safety key remain authoritative.")
#else
            Text("This app never writes to FTMS Control Point 0x2AD9. The physical console and safety key remain authoritative.")
#endif
        }
    }

    private func subscriptionColour(_ state: FTMSSubscriptionState) -> Color {
        switch state {
        case .subscribed: .green
        case .subscribing: .blue
        case .failed: .red
        case .inactive, .unsupported: .secondary
        }
    }
}

private struct DiagnosticPacketCard: View {
    let diagnostic: FTMSDiagnostic

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(FTMSUUID.name(for: diagnostic.uuid)) · 0x\(diagnostic.uuid)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(diagnostic.timestamp, format: .dateTime.hour().minute().second())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Label(diagnosticLabel, systemImage: diagnosticSymbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(diagnosticColour)
            Text(diagnostic.source.title)
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(Array(diagnostic.decodedLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(.subheadline)
            }
            LabeledContent("Raw") {
                Text(diagnostic.rawHex)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 4)
    }

    private var diagnosticLabel: String {
        switch diagnostic.kind {
        case .decoded: "Decoded"
        case .unknown: "Unknown protocol value"
        case .malformed: "Malformed packet"
        }
    }

    private var diagnosticSymbol: String {
        switch diagnostic.kind {
        case .decoded: "checkmark.circle.fill"
        case .unknown: "questionmark.circle.fill"
        case .malformed: "exclamationmark.triangle.fill"
        }
    }

    private var diagnosticColour: Color {
        switch diagnostic.kind {
        case .decoded: .green
        case .unknown: .orange
        case .malformed: .red
        }
    }
}

private struct CapabilityCard: View {
    let title: String
    let decoded: String
    let raw: String
    let issue: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(decoded)
                .font(.subheadline)
            LabeledContent("Raw") {
                Text(raw)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .multilineTextAlignment(.trailing)
            }
            if let issue {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}
