import Foundation

enum MidasConstants {
    nonisolated static let vendorID: UInt32 = 0x10C73F
    nonisolated static let veniceF32ModelID: UInt32 = 0x000001
    nonisolated static let veniceUnitSpecifierID: UInt32 = 0x10C73F
    nonisolated static let veniceUnitVersion: UInt32 = 0x000001
    nonisolated static let diceBaseAddress: UInt64 = 0xFFFFE0000000
    nonisolated static let diceExtensionOffset: UInt32 = 0x00200000
}

struct MidasCoreAudioStatus: Equatable {
    var deviceName: String
    var inputChannels: Int
    var outputChannels: Int
    var sampleRate: Double
    var bufferFrameSize: UInt32
    var inputLatency: UInt32
    var outputLatency: UInt32
    var isRunning: Bool
    var isDefaultInput: Bool
    var isDefaultOutput: Bool

    var channelSummary: String {
        "\(inputChannels) in / \(outputChannels) out"
    }

    var sampleRateSummary: String {
        sampleRate > 0 ? "\(Int(sampleRate)) Hz" : "Unknown"
    }

    static func make(from device: AudioWrapperDevice) -> MidasCoreAudioStatus {
        MidasCoreAudioStatus(
            deviceName: device.name,
            inputChannels: device.inputChannelCount,
            outputChannels: device.outputChannelCount,
            sampleRate: device.sampleRate,
            bufferFrameSize: device.bufferFrameSize,
            inputLatency: device.inputDeviceLatency,
            outputLatency: device.outputDeviceLatency,
            isRunning: device.isRunning,
            isDefaultInput: device.isDefaultInput,
            isDefaultOutput: device.isDefaultOutput
        )
    }
}

struct MidasDiscoveredIdentity {
    var guid: UInt64
    var nodeID: UInt8
    var generation: UInt32
    var vendorID: UInt32
    var modelID: UInt32
    var vendorName: String
    var modelName: String
    var units: [ASFWDriverConnector.FWUnitInfo]
    var profile: FireWireAudioDeviceProfile?

    var displayName: String {
        let name = "\(vendorName) \(modelName)".trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty { return name }
        return profile?.displayName.isEmpty == false ? profile!.displayName : "Midas Venice"
    }

    var guidHex: String { String(format: "0x%016llX", guid) }
    var vendorHex: String { String(format: "0x%06X", vendorID) }
    var modelHex: String { String(format: "0x%06X", modelID) }

    nonisolated static func make(from device: ASFWDriverConnector.FWDeviceInfo,
                                 profile: FireWireAudioDeviceProfile?) -> MidasDiscoveredIdentity {
        MidasDiscoveredIdentity(
            guid: device.guid,
            nodeID: device.nodeId,
            generation: device.generation,
            vendorID: device.vendorId,
            modelID: device.modelId,
            vendorName: device.vendorName,
            modelName: device.modelName,
            units: device.units,
            profile: profile
        )
    }
}

struct MidasPublishedDiceStatus: Equatable {
    var inner: AlesisPublishedDiceStatus

    nonisolated static func parse(_ ioregOutput: String) -> MidasPublishedDiceStatus? {
        guard intProperty("ASFWVendorID", in: ioregOutput).map(UInt32.init) == MidasConstants.vendorID,
              intProperty("ASFWModelID", in: ioregOutput).map(UInt32.init) == MidasConstants.veniceF32ModelID,
              let status = AlesisPublishedDiceStatus.parse(ioregOutput) else {
            return nil
        }
        return MidasPublishedDiceStatus(inner: status)
    }

    nonisolated private static func intProperty(_ key: String, in output: String) -> Int? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = #"""# + escaped + #""\s*=\s*([0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return Int(output[valueRange])
    }
}

struct MidasDiceProbeDiagnostic: Equatable {
    var guid: UInt64
    var vendorID: UInt32
    var modelID: UInt32
    var deviceName: String
    var protocolName: String
    var profileSource: String
    var probeState: String
    var failReason: String
    var capsSource: String
    var hostInputPcmChannels: Int
    var hostOutputPcmChannels: Int
    var deviceToHostAm824Slots: Int
    var hostToDeviceAm824Slots: Int
    var deviceToHostActiveStreams: Int
    var hostToDeviceActiveStreams: Int
    var sampleRateHz: Int
    var deviceToHostIsoChannel: Int
    var hostToDeviceIsoChannel: Int
    var attempt: Int
    var maxAttempts: Int
    var status: UInt32

    var guidHex: String { String(format: "0x%016llX", guid) }
    var vendorHex: String { String(format: "0x%06X", vendorID) }
    var modelHex: String { String(format: "0x%06X", modelID) }
    var channelSummary: String { "\(hostInputPcmChannels) in / \(hostOutputPcmChannels) out" }
    var streamSummary: String { "\(deviceToHostActiveStreams) capture / \(hostToDeviceActiveStreams) playback" }
    var slotSummary: String { "\(deviceToHostAm824Slots) capture / \(hostToDeviceAm824Slots) playback" }
    var isoSummary: String {
        "\(formatIso(deviceToHostIsoChannel)) capture / \(formatIso(hostToDeviceIsoChannel)) playback"
    }
    var attemptSummary: String {
        maxAttempts > 0 ? "\(attempt)/\(maxAttempts)" : "\(attempt)"
    }
    var statusHex: String {
        String(format: "0x%08X", status)
    }

    var humanState: String {
        switch probeState {
        case "published":
            return "CoreAudio publication allowed"
        case "refreshing", "refresh_pending":
            return "DICE probe still settling"
        case "failed":
            return humanFailReason
        default:
            return probeState
        }
    }

    var humanFailReason: String {
        switch failReason {
        case "coreaudio_publication_allowed":
            return "No failure"
        case "runtime_caps_not_ready":
            return "DICE stream caps were not ready"
        case "runtime_caps_refresh_failed":
            return "DICE stream cap read failed"
        case "runtime_caps_refresh_unsupported":
            return "Runtime cap refresh is unsupported"
        case "standard_dice_sections_read_failed":
            return "Standard DICE section table could not be read"
        case "standard_dice_sections_empty":
            return "Standard DICE section table is empty"
        case "standard_dice_sections_invalid":
            return "Standard DICE section table is incomplete"
        case "standard_dice_global_read_failed":
            return "Standard DICE global state could not be read"
        case "standard_dice_tx_read_failed":
            return "Standard DICE capture stream format could not be read"
        case "standard_dice_rx_read_failed":
            return "Standard DICE playback stream format could not be read"
        case "standard_dice_zero_caps":
            return "Standard DICE stream formats reported no active audio"
        case "extension_sections_read_failed":
            return "DICE EAP extension table could not be read"
        case "extension_sections_empty":
            return "DICE EAP extension table is empty"
        case "extension_current_config_unavailable":
            return "DICE EAP current configuration is unavailable"
        case "extension_stream_config_read_failed":
            return "DICE EAP stream configuration could not be read"
        case "extension_stream_config_empty":
            return "DICE EAP stream configuration reported no audio"
        case "extension_current_config_counts_only":
            return "DICE EAP reported channel counts but no active ISO streams"
        case "unsupported_multi_stream_geometry":
            return "Unsupported multi-stream DICE geometry"
        case "invalid_runtime_caps":
            return "Invalid DICE runtime caps"
        case "protocol_missing":
            return "No DICE protocol instance"
        default:
            return failReason
        }
    }

    var probeLadderSummary: String {
        switch failReason {
        case "coreaudio_publication_allowed":
            return "Standard DICE produced usable stream caps and CoreAudio publication was allowed."
        case "standard_dice_sections_read_failed":
            return "Stopped at standard DICE: the section table could not be read."
        case "standard_dice_sections_empty":
            return "Standard DICE section table was reachable but empty; EAP current-config was then probed."
        case "standard_dice_sections_invalid":
            return "Standard DICE section table was incomplete; EAP current-config was then probed."
        case "standard_dice_global_read_failed":
            return "Standard DICE sections were found, but global state could not be read; EAP current-config was then probed."
        case "standard_dice_tx_read_failed":
            return "Standard DICE global state was readable, but capture stream format could not be read; EAP current-config was then probed."
        case "standard_dice_rx_read_failed":
            return "Standard DICE capture format was readable, but playback stream format could not be read; EAP current-config was then probed."
        case "standard_dice_zero_caps":
            return "Standard DICE stream formats reported zero usable audio; EAP current-config was then probed."
        case "extension_sections_read_failed":
            return "Standard DICE did not produce usable caps; EAP extension table could not be read."
        case "extension_sections_empty":
            return "Standard DICE did not produce usable caps; EAP extension table was empty."
        case "extension_current_config_unavailable":
            return "Standard DICE did not produce usable caps; EAP current-config section was unavailable."
        case "extension_stream_config_read_failed":
            return "EAP current-config was present, but stream entries could not be read."
        case "extension_stream_config_empty":
            return "EAP current-config was present, but it reported no audio channels."
        case "extension_current_config_counts_only":
            return "EAP current-config reported channel counts, but not active ISO channels."
        case "unsupported_multi_stream_geometry":
            return "Usable stream caps were found, but ASFW does not yet support this multi-stream geometry."
        case "invalid_runtime_caps":
            return "Stream caps were found, but at least one required runtime value was invalid."
        case "runtime_caps_not_ready":
            return "ASFW is still waiting for runtime stream caps from DICE."
        case "runtime_caps_refresh_failed":
            return "ASFW tried to refresh runtime stream caps, but the refresh failed."
        default:
            return "Probe source \(capsSource), state \(probeState), reason \(failReason)."
        }
    }

    var publicationDecisionSummary: String {
        if probeState == "published" {
            return "CoreAudio endpoint may be published."
        }
        if failReason == "extension_current_config_counts_only" {
            return "Do not publish yet: channel counts are evidence, but ISO channel/start state is not proven."
        }
        if failReason == "unsupported_multi_stream_geometry" {
            return "Do not publish yet: ASFW needs a multi-stream DICE implementation for this device."
        }
        if hostInputPcmChannels > 0 || hostOutputPcmChannels > 0 {
            return "Do not publish yet: partial DICE evidence was found but runtime caps are not safe."
        }
        return "Do not publish yet: no usable DICE audio geometry was found."
    }

    private func formatIso(_ value: Int) -> String {
        value == 0xFF ? "invalid" : "\(value)"
    }

    nonisolated static func parse(_ ioregOutput: String) -> MidasDiceProbeDiagnostic? {
        guard let vendor = numberProperty("ASFWDICELastProbeVendorID", in: ioregOutput).map(UInt32.init),
              let model = numberProperty("ASFWDICELastProbeModelID", in: ioregOutput).map(UInt32.init),
              vendor == MidasConstants.vendorID,
              model == MidasConstants.veniceF32ModelID else {
            return nil
        }

        return MidasDiceProbeDiagnostic(
            guid: numberProperty("ASFWDICELastProbeGUID", in: ioregOutput) ?? 0,
            vendorID: vendor,
            modelID: model,
            deviceName: stringProperty("ASFWDICELastProbeDeviceName", in: ioregOutput) ?? "Midas Venice",
            protocolName: stringProperty("ASFWDICELastProbeProtocol", in: ioregOutput) ?? "TCAT DICE",
            profileSource: stringProperty("ASFWDICELastProbeProfileSource", in: ioregOutput) ?? "unknown",
            probeState: stringProperty("ASFWDICELastProbeState", in: ioregOutput) ?? "unknown",
            failReason: stringProperty("ASFWDICELastProbeFailReason", in: ioregOutput) ?? "unknown",
            capsSource: stringProperty("ASFWDICELastProbeCapsSource", in: ioregOutput) ?? "unknown",
            hostInputPcmChannels: Int(numberProperty("ASFWDICELastProbeHostInputPcmChannels", in: ioregOutput) ?? 0),
            hostOutputPcmChannels: Int(numberProperty("ASFWDICELastProbeHostOutputPcmChannels", in: ioregOutput) ?? 0),
            deviceToHostAm824Slots: Int(numberProperty("ASFWDICELastProbeDeviceToHostAm824Slots", in: ioregOutput) ?? 0),
            hostToDeviceAm824Slots: Int(numberProperty("ASFWDICELastProbeHostToDeviceAm824Slots", in: ioregOutput) ?? 0),
            deviceToHostActiveStreams: Int(numberProperty("ASFWDICELastProbeDeviceToHostActiveStreams", in: ioregOutput) ?? 0),
            hostToDeviceActiveStreams: Int(numberProperty("ASFWDICELastProbeHostToDeviceActiveStreams", in: ioregOutput) ?? 0),
            sampleRateHz: Int(numberProperty("ASFWDICELastProbeSampleRateHz", in: ioregOutput) ?? 0),
            deviceToHostIsoChannel: Int(numberProperty("ASFWDICELastProbeDeviceToHostIsoChannel", in: ioregOutput) ?? 0xFF),
            hostToDeviceIsoChannel: Int(numberProperty("ASFWDICELastProbeHostToDeviceIsoChannel", in: ioregOutput) ?? 0xFF),
            attempt: Int(numberProperty("ASFWDICELastProbeAttempt", in: ioregOutput) ?? 0),
            maxAttempts: Int(numberProperty("ASFWDICELastProbeMaxAttempts", in: ioregOutput) ?? 0),
            status: UInt32(numberProperty("ASFWDICELastProbeStatus", in: ioregOutput) ?? 0)
        )
    }

    nonisolated private static func stringProperty(_ key: String, in output: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = #"""# + escaped + #""\s*=\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return String(output[valueRange])
    }

    nonisolated private static func numberProperty(_ key: String, in output: String) -> UInt64? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = #"""# + escaped + #""\s*=\s*(0x[0-9A-Fa-f]+|[0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: output) else {
            return nil
        }

        let raw = String(output[valueRange])
        if raw.hasPrefix("0x") || raw.hasPrefix("0X") {
            return UInt64(raw.dropFirst(2), radix: 16)
        }
        return UInt64(raw)
    }
}
