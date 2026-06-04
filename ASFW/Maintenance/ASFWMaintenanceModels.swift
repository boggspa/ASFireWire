import Foundation

enum MaintenanceHelperApprovalState: String, Equatable {
    case unknown
    case notRegistered
    case requiresApproval
    case enabled
    case notFound
    case failed

    var displayName: String {
        switch self {
        case .unknown: return "Unknown"
        case .notRegistered: return "Not registered"
        case .requiresApproval: return "Needs approval"
        case .enabled: return "Enabled"
        case .notFound: return "Not found"
        case .failed: return "Failed"
        }
    }
}

enum MaintenanceHealthState: String, Equatable {
    case unknown
    case clean
    case repairNeeded
    case rebootRequired
    case uninstalled
}

struct MaintenanceAudioRuntimeTelemetry: Equatable {
    var state: String?
    var phase: String?
    var statusName: String?
    var statusCode: UInt64?
    var rxQueueStatus: UInt64?
    var txQueueStatus: UInt64?
    var attempt: UInt64?
    var guid: UInt64?
    var ok: Bool?
    var detail: String?

    var hasAnyData: Bool {
        state != nil || phase != nil || statusCode != nil || statusName != nil
    }

    var indicatesStartFailure: Bool {
        state == "failed_to_start" || (phase?.contains("start") == true && ok == false)
    }

    var indicatesStopFailure: Bool {
        state == "failed_to_stop" || (phase?.contains("stop") == true && ok == false)
    }

    var statusText: String {
        if let statusName, let statusCode {
            return "\(statusName) (0x\(String(statusCode, radix: 16)))"
        }
        if let statusName {
            return statusName
        }
        if let statusCode {
            return "0x\(String(statusCode, radix: 16))"
        }
        return "unknown"
    }
}

struct MaintenanceStateSummary: Equatable {
    var health: MaintenanceHealthState
    var activeDriver: Bool
    var driverServiceLoaded: Bool
    var staleTerminatingDriver: Bool
    var coreAudioDeviceVisible: Bool
    var activeCDHash: String?
    var expectedCDHash: String?
    var message: String

    static let unknown = MaintenanceStateSummary(
        health: .unknown,
        activeDriver: false,
        driverServiceLoaded: false,
        staleTerminatingDriver: false,
        coreAudioDeviceVisible: false,
        activeCDHash: nil,
        expectedCDHash: nil,
        message: "Driver state has not been checked yet."
    )
}

enum MaintenanceOperationOutcome: Equatable {
    case succeeded(message: String, snapshotPath: String?)
    case repairNeeded(message: String, snapshotPath: String?)
    case rebootRequired(message: String, snapshotPath: String?)
    case failed(message: String, snapshotPath: String?)

    var message: String {
        switch self {
        case .succeeded(let message, _),
             .repairNeeded(let message, _),
             .rebootRequired(let message, _),
             .failed(let message, _):
            return message
        }
    }

    var snapshotPath: String? {
        switch self {
        case .succeeded(_, let path),
             .repairNeeded(_, let path),
             .rebootRequired(_, let path),
             .failed(_, let path):
            return path
        }
    }
}

struct ASFWMaintenanceParser {
    static func hasActiveDriver(systemExtensions: String, driverBundleID: String) -> Bool {
        systemExtensions
            .split(separator: "\n")
            .contains { line in
                lineMatchesDriverBundle(line, driverBundleID: driverBundleID)
                && line.contains("[activated enabled]")
                && !line.contains("terminating for uninstall")
            }
    }

    static func hasStaleTerminatingDriver(systemExtensions: String, driverBundleID: String) -> Bool {
        systemExtensions
            .split(separator: "\n")
            .contains { line in
                lineMatchesDriverBundle(line, driverBundleID: driverBundleID)
                && line.localizedCaseInsensitiveContains("terminating for uninstall")
            }
    }

    private static func lineMatchesDriverBundle(_ line: Substring, driverBundleID: String) -> Bool {
        guard !driverBundleID.isEmpty else { return false }
        return line.split(whereSeparator: \.isWhitespace)
            .contains { token in
                String(token) == driverBundleID || String(token) == "\(driverBundleID),"
            }
    }

    static func activeCDHash(ioregOutput: String) -> String? {
        activeCDHash(ioregOutput: ioregOutput, driverBundleID: nil)
    }

    static func hasDriverService(ioregOutput: String, driverBundleID: String?) -> Bool {
        if let driverBundleID,
           !driverBundleID.isEmpty {
            let driverBlocks = ioregOutput.components(separatedBy: "+-o ASFWDriver").dropFirst()
            for rawBlock in driverBlocks {
                let block = "+-o ASFWDriver" + rawBlock
                if block.contains(#""CFBundleIdentifier" = "\#(driverBundleID)""#)
                    || block.contains(#""IOUserServerName" = "\#(driverBundleID)""#)
                    || block.contains(#""IOPersonalityPublisher" = "\#(driverBundleID)""#) {
                    return true
                }
            }

            if ioregOutput.contains(#""CFBundleIdentifier" = ""#)
                || ioregOutput.contains(#""IOUserServerName" = ""#) {
                return false
            }
        }

        return ioregOutput.contains("ASFWDriver") || firstCDHash(in: ioregOutput) != nil
    }

    static func activeCDHash(ioregOutput: String, driverBundleID: String?) -> String? {
        if let driverBundleID,
           !driverBundleID.isEmpty {
            let driverBlocks = ioregOutput.components(separatedBy: "+-o ASFWDriver").dropFirst()
            for rawBlock in driverBlocks {
                let block = "+-o ASFWDriver" + rawBlock
                let matchesBundle =
                    block.contains(#""CFBundleIdentifier" = "\#(driverBundleID)""#)
                    || block.contains(#""IOUserServerName" = "\#(driverBundleID)""#)
                    || block.contains(#""IOPersonalityPublisher" = "\#(driverBundleID)""#)
                if matchesBundle {
                    return firstCDHash(in: block)
                }
            }

            if ioregOutput.contains(#""CFBundleIdentifier" = ""#)
                || ioregOutput.contains(#""IOUserServerName" = ""#) {
                return nil
            }
        }

        return firstCDHash(in: ioregOutput)
    }

    private static func firstCDHash(in ioregOutput: String) -> String? {
        let pattern = #""IOUserServerCDHash"\s*=\s*"([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(ioregOutput.startIndex..<ioregOutput.endIndex, in: ioregOutput)
        guard let match = regex.firstMatch(in: ioregOutput, range: range),
              match.numberOfRanges > 1,
              let hashRange = Range(match.range(at: 1), in: ioregOutput) else {
            return nil
        }
        return String(ioregOutput[hashRange])
    }

    static func coreAudioContainsDevice(systemProfilerOutput: String,
                                        deviceName: String?) -> Bool {
        guard let deviceName,
              !deviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        return systemProfilerOutput.localizedCaseInsensitiveContains(deviceName)
    }

    static func coreAudioContainsDevice(systemProfilerOutput: String,
                                        deviceName: String = "Alesis MultiMix Firewire") -> Bool {
        coreAudioContainsDevice(systemProfilerOutput: systemProfilerOutput,
                                deviceName: Optional(deviceName))
    }

    static func audioRuntimeTelemetry(driverIoregOutput: String,
                                      audioNubIoregOutput: String) -> MaintenanceAudioRuntimeTelemetry? {
        let output = [audioNubIoregOutput, driverIoregOutput]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n")
        let telemetry = MaintenanceAudioRuntimeTelemetry(
            state: stringProperty("ASFWAudioRuntimeState", in: output),
            phase: stringProperty("ASFWAudioRuntimePhase", in: output),
            statusName: stringProperty("ASFWAudioLastStatusName", in: output),
            statusCode: unsignedIntegerProperty("ASFWAudioLastStatus", in: output),
            rxQueueStatus: unsignedIntegerProperty("ASFWAudioLastRxQueueStatus", in: output),
            txQueueStatus: unsignedIntegerProperty("ASFWAudioLastTxQueueStatus", in: output),
            attempt: unsignedIntegerProperty("ASFWAudioRuntimeAttempt", in: output),
            guid: unsignedIntegerProperty("ASFWAudioRuntimeGUID", in: output),
            ok: boolProperty("ASFWAudioRuntimeOK", in: output),
            detail: stringProperty("ASFWAudioRuntimeDetail", in: output)
        )
        return telemetry.hasAnyData ? telemetry : nil
    }

    static func stringProperty(_ key: String, in output: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = #""\#(escaped)"\s*=\s*"([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        return String(output[valueRange])
    }

    static func unsignedIntegerProperty(_ key: String, in output: String) -> UInt64? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = #""\#(escaped)"\s*=\s*(0x[0-9a-fA-F]+|\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        let value = String(output[valueRange])
        if value.hasPrefix("0x") || value.hasPrefix("0X") {
            return UInt64(String(value.dropFirst(2)), radix: 16)
        }
        return UInt64(value)
    }

    static func boolProperty(_ key: String, in output: String) -> Bool? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = #""\#(escaped)"\s*=\s*(Yes|No|true|false|1|0)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(output.startIndex..<output.endIndex, in: output)
        guard let match = regex.firstMatch(in: output, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: output) else {
            return nil
        }
        switch String(output[valueRange]).lowercased() {
        case "yes", "true", "1":
            return true
        case "no", "false", "0":
            return false
        default:
            return nil
        }
    }

    static func summarize(systemExtensions: String,
                          ioregOutput: String,
                          coreAudioOutput: String,
                          expectedCDHash: String?,
                          driverBundleID: String,
                          expectedCoreAudioDeviceName: String? = "Alesis MultiMix Firewire") -> MaintenanceStateSummary {
        let active = hasActiveDriver(systemExtensions: systemExtensions, driverBundleID: driverBundleID)
        let stale = hasStaleTerminatingDriver(systemExtensions: systemExtensions, driverBundleID: driverBundleID)
        let serviceLoaded = hasDriverService(ioregOutput: ioregOutput, driverBundleID: driverBundleID)
        let cdHash = activeCDHash(ioregOutput: ioregOutput, driverBundleID: driverBundleID)
        let coreAudioVisible = coreAudioContainsDevice(systemProfilerOutput: coreAudioOutput,
                                                       deviceName: expectedCoreAudioDeviceName)
        let expected = expectedCDHash?.isEmpty == false ? expectedCDHash : nil
        let cdHashMismatch = expected != nil && cdHash != nil && cdHash != expected

        if stale {
            return MaintenanceStateSummary(
                health: .rebootRequired,
                activeDriver: active,
                driverServiceLoaded: serviceLoaded,
                staleTerminatingDriver: true,
                coreAudioDeviceVisible: coreAudioVisible,
                activeCDHash: cdHash,
                expectedCDHash: expected,
                message: "macOS still has an ASFW driver terminating for uninstall. Reboot before another install attempt."
            )
        }

        if active && !serviceLoaded {
            return MaintenanceStateSummary(
                health: .repairNeeded,
                activeDriver: true,
                driverServiceLoaded: false,
                staleTerminatingDriver: false,
                coreAudioDeviceVisible: coreAudioVisible,
                activeCDHash: nil,
                expectedCDHash: expected,
                message: "ASFW system extension is installed, but the driver service is not loaded."
            )
        }

        if active && serviceLoaded && !cdHashMismatch && coreAudioVisible {
            return MaintenanceStateSummary(
                health: .clean,
                activeDriver: true,
                driverServiceLoaded: true,
                staleTerminatingDriver: false,
                coreAudioDeviceVisible: true,
                activeCDHash: cdHash,
                expectedCDHash: expected,
                message: "ASFW driver and CoreAudio device look healthy."
            )
        }

        if !active && cdHash == nil && !coreAudioVisible {
            return MaintenanceStateSummary(
                health: .uninstalled,
                activeDriver: false,
                driverServiceLoaded: false,
                staleTerminatingDriver: false,
                coreAudioDeviceVisible: false,
                activeCDHash: nil,
                expectedCDHash: expected,
                message: "ASFW driver is not active."
            )
        }

        return MaintenanceStateSummary(
            health: .repairNeeded,
            activeDriver: active,
            driverServiceLoaded: serviceLoaded,
            staleTerminatingDriver: false,
            coreAudioDeviceVisible: coreAudioVisible,
            activeCDHash: cdHash,
            expectedCDHash: expected,
            message: "ASFW driver state needs repair or refresh."
        )
    }
}
