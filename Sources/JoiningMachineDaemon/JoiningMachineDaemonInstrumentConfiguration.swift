import Foundation
import MIDI2CITransport
import MIDI2Transports

/// Native composition boundary for the Chapter 141 joining instrument.
///
/// The host must supply the already-signed, Store-derived readiness property. This type only composes the existing
/// responder and lifecycle runtime; it does not create identity, persist receipts, install artifacts, or inspect the
/// opaque receiver.
public struct JoiningMachineDaemonInstrumentConfiguration: Sendable {
    public let muid: UInt32
    public let softwareRevision: UInt32
    public let endpoint: String
    public let readinessPropertyData: Data
    public let maxDataPerMessage: Int
    public let hostManifest: JoiningMachineInstrumentHostManifest
    public let hostManifestPropertyData: Data

    public static var platform: String {
        #if os(Linux)
        return "Linux"
        #elseif os(macOS)
        return "macOS"
        #elseif os(iOS)
        return "iOS"
        #else
        return "unsupported"
        #endif
    }

    public init(muid: UInt32, softwareRevision: UInt32, endpoint: String, readinessPropertyData: Data,
                maxDataPerMessage: Int = 80, transport: String = "RTP-MIDI2") throws {
        guard endpoint.hasPrefix("midi2://") else { throw JoiningMachineDaemonError.invalidEndpoint }
        guard !readinessPropertyData.isEmpty else { throw JoiningMachineDaemonError.readinessPropertyMissing }
        guard muid != 0, softwareRevision != 0 else { throw JoiningMachineInstrumentIdentityError.invalid }
        // The pinned MIDI2 PE SysEx8 codec uses an eight-bit chunk length.
        // Reject invalid configuration rather than truncate data or trap in encoding.
        guard (1...255).contains(maxDataPerMessage) else { throw JoiningMachineDaemonError.invalidPropertyChunkSize }
        self.muid = muid
        self.softwareRevision = softwareRevision
        self.endpoint = endpoint
        self.readinessPropertyData = readinessPropertyData
        self.maxDataPerMessage = maxDataPerMessage
        self.hostManifest = try .reference(
            platform: Self.platform,
            transport: transport,
            supportedTransports: ["RTP-MIDI2", "Network-MIDI2-UDP"])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.hostManifestPropertyData = try encoder.encode(hostManifest)
    }

    public func makeResponder() -> MIDI2CIResponder {
        MIDI2CIResponder(
            muid: muid,
            softwareRevision: softwareRevision,
            supportedProfiles: ["fountaincoach.joining-machine@0.1.0"],
            properties: [MIDI2CIResponder.joiningMachineReadinessResource: readinessPropertyData,
                         MIDI2CIResponder.joiningMachineHostManifestResource: hostManifestPropertyData],
            maxDataPerMessage: maxDataPerMessage,
            endpointMaxGroups: UInt8(hostManifest.maxGroups),
            functionBlockCount: UInt8(hostManifest.functionBlocks))
    }

    public func makeRuntime(transport: any MIDITransport,
                            lifecycleSink: JoiningMachineDaemonRuntime.LifecycleSink? = nil) throws
        -> JoiningMachineDaemonRuntime {
        try JoiningMachineDaemonRuntime(
            transport: transport,
            responder: makeResponder(),
            endpoint: endpoint,
            lifecycleSink: lifecycleSink)
    }
}
