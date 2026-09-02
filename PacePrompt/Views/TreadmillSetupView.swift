import SwiftUI

struct TreadmillSetupView: View {
    @ObservedObject var treadmill: TreadmillSetupViewModel

    var body: some View {
        List {
            statusSection
            discoverySection

            if treadmill.canDisconnect {
                connectionSection
            }

            capabilitySection

            if !treadmill.diagnostics.isEmpty {
                notificationSection
            }

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

    private var notificationSection: some View {
        Section("Passive notifications") {
            ForEach(treadmill.diagnostics) { diagnostic in
                CapabilityCard(
                    title: "\(FTMSUUID.name(for: diagnostic.uuid)) · 0x\(diagnostic.uuid)",
                    decoded: diagnostic.decoded,
                    raw: diagnostic.rawHex,
                    issue: diagnostic.isMalformed ? diagnostic.decoded : nil
                )
            }
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

    private var safetySection: some View {
        Section {
            Label("Read-only capability check", systemImage: "lock.shield")
        } footer: {
            Text("This app never writes to FTMS Control Point 0x2AD9. The physical console and safety key remain authoritative.")
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
