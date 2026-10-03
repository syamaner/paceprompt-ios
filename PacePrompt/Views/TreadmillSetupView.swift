import SwiftUI
import UIKit

struct TreadmillSetupView: View {
    @ObservedObject var treadmill: TreadmillSetupViewModel

    var body: some View {
        List {
            statusSection
            discoverySection

            if treadmill.canDisconnect {
                connectionSection
            }

            if let profiles = treadmill.planningProfiles {
                Section {
                    if let failure = profiles.failure { Label(failure.message, systemImage: "exclamationmark.triangle") }
                    NavigationLink("Saved treadmills") { PlanningProfilesView(model: profiles) }
                        .frame(minHeight: 44).accessibilityIdentifier("profiles.manage")
                }
            }
            supportedSettingsSection
            readingAvailabilitySection
            Section {
                NavigationLink {
                    TreadmillTroubleshootingView(treadmill: treadmill)
                } label: {
                    Label("Troubleshooting", systemImage: "wrench.and.screwdriver")
                        .frame(minHeight: 44)
                }
                .accessibilityIdentifier("setup.troubleshooting")
            } footer: {
                Text("Connection details and diagnostic captures for investigating a problem.")
            }
            safetySection
        }
        .modifier(OptionalPlanningProfileDiscoveryPresentation(model: treadmill.planningProfiles))
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
            if treadmill.lastError != nil {
                Label("Could not complete the treadmill check. Check Bluetooth, then reconnect to try again. Details are in Troubleshooting.", systemImage: "exclamationmark.triangle.fill")
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
                    treadmill.isScanning ? "Stop scanning" : "Find treadmills",
                    systemImage: treadmill.isScanning ? "stop.circle" : "dot.radiowaves.left.and.right"
                )
            }
            .disabled(!treadmill.canScan && !treadmill.isScanning)

            if treadmill.isScanning && treadmill.devices.isEmpty {
                HStack {
                    ProgressView()
                    Text("Looking for nearby treadmills")
                        .foregroundStyle(.secondary)
                }
            }

            ForEach(treadmill.devices) { device in
                Button {
                    treadmill.connect(to: device)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name)
                            .foregroundStyle(.primary)
                    }
                }
            }
        } header: {
            Text("Discovery")
        } footer: {
            Text("Find nearby treadmills, then choose yours. Supported settings are checked after connecting.")
        }
    }

    private var connectionSection: some View {
        Section {
            Button("Disconnect", role: .destructive) {
                treadmill.disconnect()
            }
        }
    }

    private var supportedSettingsSection: some View {
        Section("Supported settings") {
            settingSummary("Speed", support: treadmill.speedTargetSettingText,
                           range: treadmill.speedRangeText, rangeUnreadable: treadmill.speedRange.issue != nil)
            settingSummary("Incline", support: treadmill.inclinationTargetSettingText,
                           range: treadmill.inclinationRangeText, rangeUnreadable: treadmill.inclinationRange.issue != nil)
        }
    }

    private func settingSummary(_ title: String, support: String, range: String, rangeUnreadable: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            Text("Adjustment: \(treadmill.featureFlags.issue != nil ? "Could not read" : support)")
            Text(rangeUnreadable ? "Could not read the limits. Reconnect to try again." : range)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("setup.\(title.lowercased()).limits")
    }

    private var readingAvailabilitySection: some View {
        Section {
            ForEach(treadmill.subscriptions) { subscription in
                VStack(alignment: .leading, spacing: 6) {
                    Text(readingTitle(subscription.uuid)).font(.headline)
                    Text(readingStatus(subscription.state))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("setup.reading.\(subscription.uuid)")
            }
        } header: {
            Text("Reading availability")
        } footer: {
            Text("Ready to receive means updates are enabled. It does not confirm a current reading or that the belt has stopped.")
        }
    }

    private func readingTitle(_ uuid: String) -> String {
        switch uuid {
        case FTMSUUID.treadmillData: "Speed and distance"
        case FTMSUUID.trainingStatus: "Workout status"
        default: "Treadmill status"
        }
    }

    private func readingStatus(_ state: FTMSSubscriptionState) -> String {
        switch state {
        case .subscribed: "Ready to receive updates"
        case .subscribing: "Connecting to readings…"
        case .failed: "Could not receive updates. Reconnect to try again."
        case .inactive: "Not receiving updates"
        case .unsupported: "Live updates not available"
        }
    }

    private var safetySection: some View {
        Section {
            Label("Setup does not control the belt", systemImage: "lock.shield")
        } footer: {
            Text("Start a workout separately from a saved plan. Always use the treadmill console and safety key to start or stop the belt.")
        }
    }
}

private struct TreadmillTroubleshootingView: View {
    @ObservedObject var treadmill: TreadmillSetupViewModel
    @State private var copiedDiagnostics = false
    @State private var copiedFreshnessCapture = false

    var body: some View {
        List {
            Section {
                Text("Captures can include treadmill names, device identifiers, timestamps and readings. They stay in memory until you explicitly copy or share them. Choose a recipient you trust.")
                    .accessibilityIdentifier("troubleshooting.privacy")
            }
            if let error = treadmill.lastError {
                Section("Last reported error") {
                    Text(error).textSelection(.enabled)
                        .accessibilityIdentifier("troubleshooting.error")
                }
            }
            freshnessCaptureSection
            Section("Discovered devices") {
                ForEach(treadmill.devices) { device in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(device.name)
                        Text(device.id.uuidString).font(.caption.monospaced()).textSelection(.enabled)
                        Text("Signal: \(device.rssi) dBm").font(.caption)
                    }
                }
            }
            capabilitySection
            subscriptionSection
            if !treadmill.characteristics.isEmpty { characteristicSection }
            diagnosticSection
        }
        .navigationTitle("Troubleshooting")
        .navigationBarTitleDisplayMode(.inline)
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
                Button("Clear in-memory capture", role: .destructive) {
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

    private var freshnessCaptureSection: some View {
        Section {
            LabeledContent("Application state", value: treadmill.applicationActivity.title)
            LabeledContent(
                "Complete packet capture",
                value: "\(treadmill.capturedDiagnosticCount)/\(treadmill.captureDiagnosticCapacity)"
            )
            if treadmill.droppedCaptureDiagnostics > 0 {
                Label(
                    "\(treadmill.droppedCaptureDiagnostics) packets dropped; this capture is not complete",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote)
                .foregroundStyle(.red)
            }

            Menu {
                ForEach(FTMSOperatorObservation.allCases) { observation in
                    Button(observation.title) {
                        treadmill.recordOperatorObservation(observation)
                        copiedFreshnessCapture = false
                    }
                }
            } label: {
                Label("Record operator observation", systemImage: "person.crop.circle.badge.checkmark")
            }
            .accessibilityIdentifier("troubleshooting.observation")
            .disabled(!treadmill.canRecordOperatorObservation)

            ShareLink(item: treadmill.treadmillDataFreshnessReport) {
                Label("Share reading capture", systemImage: "square.and.arrow.up")
            }

            Button {
                UIPasteboard.general.string = treadmill.treadmillDataFreshnessReport
                copiedFreshnessCapture = true
            } label: {
                Label(
                    copiedFreshnessCapture ? "Reading capture copied" : "Copy reading capture",
                    systemImage: "doc.on.doc"
                )
            }
        } header: {
            Text("Reading capture")
        } footer: {
            Text("Observations record what you report; they do not verify belt state or allow a workout to begin or end. Timing uses a monotonic clock. These tools do not control the treadmill or change workout safety checks.")
        }
    }

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
            Text(packetTiming)
                .font(.caption.monospacedDigit())
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

    private var packetTiming: String {
        var text = String(format: "+%.3f s from capture start", diagnostic.captureOffsetSeconds)
        if let interval = diagnostic.intervalSincePreviousTreadmillNotificationSeconds {
            text += String(format: " · %.3f s since prior 0x2ACD notification", interval)
        }
        return text
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
