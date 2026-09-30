import Foundation
import MIDI2
import MIDI2CITransport

/// A local codec/responder diagnostic. It opens no network transport, writes no
/// Store receipt, and cannot establish authenticated peer or machine admission.
public struct JoiningMachineDaemonSelfTestReport: Codable, Equatable, Sendable {
    public let scope: String
    public let checks: [String]
    public let unestablished: [String]
    public let manifest: JoiningMachineInstrumentHostManifest
}

public enum JoiningMachineDaemonSelfTestError: Error, Equatable {
    case failed(String)
}

public enum JoiningMachineDaemonSelfTest {
    public static func run(configuration: JoiningMachineDaemonInstrumentConfiguration) throws
        -> JoiningMachineDaemonSelfTestReport {
        let responder = configuration.makeResponder()
        return try run(configuration: configuration, exchange: responder.receive(words:))
    }

    // Injection is internal: negative tests can corrupt the wire exchange, while
    // production always exercises the same responder configuration as the daemon.
    static func run(configuration: JoiningMachineDaemonInstrumentConfiguration,
                    exchange: ([UInt32]) -> [[UInt32]]) throws -> JoiningMachineDaemonSelfTestReport {
        func replies(_ request: MIDI2CITransport.Envelope, check: String) throws -> [MIDI2CITransport.Envelope] {
            let packets = exchange(try MIDI2CITransport.encode(request))
            guard !packets.isEmpty else { throw JoiningMachineDaemonSelfTestError.failed(check) }
            return try packets.map {
                guard let reply = MIDI2CITransport.decode(words: $0) else {
                    throw JoiningMachineDaemonSelfTestError.failed(check)
                }
                return reply
            }
        }
        func single(_ request: MIDI2CITransport.Envelope, check: String) throws -> MIDI2CITransport.Envelope {
            let response = try replies(request, check: check)
            guard response.count == 1 else { throw JoiningMachineDaemonSelfTestError.failed(check) }
            return response[0]
        }
        let discovery = try single(MIDI2CITransport.discovery(muid: 1, softwareRevision: 1), check: "discovery")
        guard case .discovery(let identity) = discovery.body,
              identity.muid == configuration.muid,
              identity.softwareRev == configuration.softwareRevision else {
            throw JoiningMachineDaemonSelfTestError.failed("discovery")
        }
        let endpointRequest = EndpointDiscoveryMessage(majorVersion: 1, minorVersion: 0, maxGroups: 0xF)
            .ump(group: Uint4(0)!)
        let streamReplies = configuration.makeResponder().receive(words: [endpointRequest.word])
        guard streamReplies.count == 2,
              let endpoint = streamReplies.first.flatMap({ $0.first }).flatMap({ EndpointDiscoveryMessage(ump: UmpPacket32(word: $0)) }),
              endpoint.maxGroups == UInt8(configuration.hostManifest.maxGroups),
              let endpointInfo = streamReplies.dropFirst().first.flatMap({ $0.first }).flatMap({ EndpointInfoNotification(ump: UmpPacket32(word: $0)) }),
              endpointInfo.numberOfFunctionBlocks == UInt8(configuration.hostManifest.functionBlocks),
              endpointInfo.midi2Supported,
              !endpointInfo.jrTimestampsRx,
              !endpointInfo.jrTimestampsTx else {
            throw JoiningMachineDaemonSelfTestError.failed("endpoint-discovery")
        }
        let functionBlockRequest = FunctionBlockDiscovery(filterBitmap: 0).umps(group: Uint4(0)!)
        guard configuration.makeResponder().receive(words: [functionBlockRequest[0].word]).isEmpty,
              configuration.makeResponder().receive(words: [functionBlockRequest[1].word]).isEmpty else {
            throw JoiningMachineDaemonSelfTestError.failed("function-block-discovery")
        }
        for profileID in configuration.hostManifest.profiles {
            let reply = try single(MIDI2CITransport.profileInquiry(profileID: profileID), check: "profiles")
            guard case .profiles(let profile) = reply.body, profile.command == .reply,
                  profile.profileId == profileID, profile.details?["supported"] == 1 else {
                throw JoiningMachineDaemonSelfTestError.failed("profiles")
            }
        }
        func property(resource: String, expected: Data, requestID: UInt32) throws {
            let response = try replies(MIDI2CITransport.propertyGet(resource: resource, requestID: requestID),
                                       check: "property-readback")
            var actual = Data()
            for (index, envelope) in response.enumerated() {
                guard case .propertyExchange(let chunk) = envelope.body,
                      chunk.command == .getReply, chunk.requestId == requestID, chunk.encoding == .json,
                      chunk.header["res"] == resource,
                      chunk.header["total"] == String(expected.count),
                      chunk.header["offset"] == String(actual.count),
                      chunk.header["length"] == String(chunk.data.count),
                      chunk.header["more"] == (index == response.count - 1 ? "0" : "1"),
                      !chunk.data.isEmpty else {
                    throw JoiningMachineDaemonSelfTestError.failed("property-readback")
                }
                actual.append(contentsOf: MIDI2CITransport.decodeProperty(chunk.data, using: chunk.encoding))
            }
            guard actual == expected else { throw JoiningMachineDaemonSelfTestError.failed("property-readback") }
        }
        try property(resource: MIDI2CIResponder.joiningMachineReadinessResource,
                     expected: configuration.readinessPropertyData, requestID: 1)
        try property(resource: MIDI2CIResponder.joiningMachineHostManifestResource,
                     expected: configuration.hostManifestPropertyData, requestID: 2)
        let inquiry = try single(MIDI2CITransport.processInquiry(), check: "process-inquiry")
        guard case .processInquiry(let process) = inquiry.body, process.command == .capReply else {
            throw JoiningMachineDaemonSelfTestError.failed("process-inquiry")
        }
        func refused(_ request: MIDI2CITransport.Envelope) throws {
            let reply = try single(request, check: "read-only-refusal")
            guard case .ackNak(let ack) = reply.body, !ack.ack else {
                throw JoiningMachineDaemonSelfTestError.failed("read-only-refusal")
            }
        }
        try refused(MIDI2CITransport.propertyGet(resource: "com.fountaincoach.joining-machine/unknown", requestID: 3))
        try refused(MIDI2CITransport.Envelope(scope: .nonRealtime, subId2: 0x7C, body: .propertyExchange(
            MIDI2CITransport.PropertyExchangeBody(command: .set, requestId: 4, encoding: .json,
                header: ["res": MIDI2CIResponder.joiningMachineHostManifestResource], data: []))))
        // Read-back after the refused write must still be identical.
        try property(resource: MIDI2CIResponder.joiningMachineHostManifestResource,
                     expected: configuration.hostManifestPropertyData, requestID: 5)
        return JoiningMachineDaemonSelfTestReport(
            scope: "local-codec-responder-only",
            checks: ["discovery", "endpoint-discovery", "function-block-discovery", "profiles",
                     "readiness-readback", "host-manifest-readback", "process-inquiry", "read-only-refusal"],
            unestablished: ["authenticated-peer", "target-binding", "endpoint-function-block-discovery",
                            "network-transport", "store-admission", "hardware-interoperability"],
            manifest: configuration.hostManifest)
    }
}
