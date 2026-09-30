import Foundation

public enum JoiningMachineInstrument {
    public static let identity = "fountaincoach.joining-machine@0.1.0"
    public static let version = "0.1.0"
}

public struct JoiningMachineInstrumentIdentity: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let instrumentID: String
    public let muid: UInt32
    public let softwareRevision: UInt32

    public init(id: String = "local", muid: UInt32, softwareRevision: UInt32) throws {
        guard !id.isEmpty, muid != 0, softwareRevision != 0 else { throw JoiningMachineInstrumentIdentityError.invalid }
        self.id = id
        self.instrumentID = JoiningMachineInstrument.identity
        self.muid = muid
        self.softwareRevision = softwareRevision
    }
}

public enum JoiningMachineInstrumentIdentityError: Error, Equatable, Sendable {
    case invalid
    case instrumentMismatch
}

public struct JoiningMachineInstrumentHostManifest: Codable, Equatable, Sendable {
    public let instrumentID: String
    public let instrumentVersion: String
    public let platform: String
    public let runtime: String
    public let transport: String
    public let supportedTransports: [String]
    public let midiProtocols: [String]
    public let profiles: [String]
    public let propertyExchange: Bool
    public let processInquiry: Bool
    public let jitterReduction: Bool
    public let maxGroups: Int
    public let functionBlocks: Int

    public init(platform: String, runtime: String, transport: String,
                supportedTransports: [String] = [], midiProtocols: [String], profiles: [String],
                propertyExchange: Bool, processInquiry: Bool, jitterReduction: Bool,
                maxGroups: Int, functionBlocks: Int) throws {
        let declaredTransports = supportedTransports.isEmpty ? [transport] : supportedTransports
        guard !platform.isEmpty, !runtime.isEmpty, !transport.isEmpty,
              !declaredTransports.isEmpty, !midiProtocols.isEmpty, !profiles.isEmpty,
              Set(declaredTransports).count == declaredTransports.count,
              Set(midiProtocols).count == midiProtocols.count,
              Set(profiles).count == profiles.count, maxGroups > 0, functionBlocks >= 0 else {
            throw JoiningMachineInstrumentHostManifestError.invalid
        }
        instrumentID = JoiningMachineInstrument.identity
        instrumentVersion = JoiningMachineInstrument.version
        self.platform = platform
        self.runtime = runtime
        self.transport = transport
        self.supportedTransports = declaredTransports.sorted()
        self.midiProtocols = midiProtocols.sorted()
        self.profiles = profiles.sorted()
        self.propertyExchange = propertyExchange
        self.processInquiry = processInquiry
        self.jitterReduction = jitterReduction
        self.maxGroups = maxGroups
        self.functionBlocks = functionBlocks
    }

    public static func reference(platform: String, transport: String,
                                 supportedTransports: [String] = []) throws -> Self {
        try Self(platform: platform, runtime: "Swift", transport: transport,
                 supportedTransports: supportedTransports,
                 midiProtocols: ["MIDI-CI over UMP/SysEx8"],
                 profiles: [JoiningMachineInstrument.identity], propertyExchange: true,
                 processInquiry: true, jitterReduction: false, maxGroups: 1, functionBlocks: 0)
    }
}

public enum JoiningMachineInstrumentHostManifestError: Error, Equatable, Sendable { case invalid }
