import Foundation
import MIDI2
import MIDI2CI

/// The reusable standard MIDI-CI server boundary for a Fountain Coach instrument.
///
/// This type deliberately owns only wire-level MIDI-CI behavior. Readiness and identity are supplied by the
/// instrument host, so a responder cannot manufacture admission or persist a second Store. The host may therefore
/// use the same responder on macOS or Linux above `RTPMidiSession`.
public struct MIDI2CIResponder: Sendable {
    public static let joiningMachineReadinessResource = "com.fountaincoach.joining-machine/readiness"
    public static let joiningMachineIdentityResource = "com.fountaincoach.joining-machine/identity"
    public static let joiningMachineHostManifestResource = "com.fountaincoach.joining-machine/host-manifest"

    public let muid: UInt32
    public let softwareRevision: UInt32
    public let supportedProfiles: Set<String>
    public let endpointMaxGroups: UInt8
    public let functionBlockCount: UInt8
    private let properties: [String: Data]
    private let maxDataPerMessage: Int

    public init(muid: UInt32,
                softwareRevision: UInt32,
                supportedProfiles: Set<String>,
                properties: [String: Data],
                maxDataPerMessage: Int = 80,
                endpointMaxGroups: UInt8 = 1,
                functionBlockCount: UInt8 = 0) {
        self.muid = muid
        self.softwareRevision = softwareRevision
        self.supportedProfiles = supportedProfiles
        self.endpointMaxGroups = endpointMaxGroups
        self.functionBlockCount = functionBlockCount
        self.properties = properties
        self.maxDataPerMessage = max(1, maxDataPerMessage)
    }

    /// Handles one complete UMP request and returns zero or more complete UMP replies.
    /// Invalid or non-MIDI-CI input is ignored; unsupported typed requests receive a MIDI-CI negative acknowledgement.
    public func receive(words: [UInt32]) -> [[UInt32]] {
        if words.count == 1 {
            let packet = UmpPacket32(word: words[0])
            guard packet.header.messageType == 0xF else {
                guard let envelope = MIDI2CITransport.decode(words: words) else { return [] }
                return replies(for: envelope)
            }
            return streamReplies(for: packet)
        }
        guard let envelope = MIDI2CITransport.decode(words: words) else { return [] }
        return replies(for: envelope)
    }

    private func streamReplies(for packet: UmpPacket32) -> [[UInt32]] {
        guard let body = StreamBody(ump: packet) else { return [] }
        switch body.opcode {
        case .endpointDiscovery:
            guard let request = EndpointDiscoveryMessage(ump: packet) else { return [] }
            let groups = min(request.maxGroups, endpointMaxGroups)
            let discovery = EndpointDiscoveryMessage(
                majorVersion: request.majorVersion, minorVersion: request.minorVersion,
                maxGroups: groups).ump(group: packet.header.group)
            guard let info = try? EndpointInfoNotification(
                staticFunctionBlocks: functionBlockCount > 0,
                numberOfFunctionBlocks: functionBlockCount,
                midi1Supported: false,
                midi2Supported: true,
                jrTimestampsRx: false,
                jrTimestampsTx: false).ump(group: packet.header.group) else { return [] }
            return [[discovery.word], [info.word]]
        case .functionBlockDiscovery:
            // The zero-block instrument has a deliberate empty response. A
            // future non-zero block model must add typed descriptors first.
            return []
        default:
            return []
        }
    }

    public func replies(for envelope: MIDI2CITransport.Envelope) -> [[UInt32]] {
        switch envelope.body {
        case .discovery:
            let advertisement = MIDI2CITransport.discovery(
                muid: muid,
                softwareRevision: softwareRevision
            )
            guard case .discovery(let body) = advertisement.body,
                  let discoveryResponder = try? MidiCiDiscoveryResponder(advertisement: body),
                  let response = discoveryResponder.respond(to: envelope) else {
                return []
            }
            return encode(response)
        case .profiles(let body):
            guard body.command == .inquiry else { return [] }
            return encode(MIDI2CITransport.profileReply(
                for: body,
                supported: supportedProfiles.contains(body.profileId)))
        case .propertyExchange(let body):
            return propertyReplies(for: body)
        case .processInquiry(let body):
            switch body.command {
            case .capInquiry:
                return encode(MIDI2CITransport.processInquiryReply(filters: ["messageDataControl": 0x7F]))
            case .messageReport:
                return encode(MIDI2CITransport.processMessageReportReply(filters: body.filters ?? [:]))
            default:
                return []
            }
        case .ackNak:
            return []
        }
    }

    private func propertyReplies(for body: MIDI2CITransport.PropertyExchangeBody) -> [[UInt32]] {
        let resource = body.header["res"] ?? ""
        guard let data = properties[resource] else {
            return encode(MIDI2CITransport.negativeAcknowledgment(statusCode: 1, message: "unsupported property"))
        }
        switch body.command {
        case .get:
            return MIDI2CITransport.propertyGetReplies(
                resource: resource,
                requestID: body.requestId,
                data: Array(data),
                encoding: body.encoding,
                maxDataPerMessage: maxDataPerMessage).flatMap(encode)
        case .set, .subscribe, .terminate:
            return encode(MIDI2CITransport.negativeAcknowledgment(statusCode: 2, message: "read-only property"))
        default:
            return encode(MIDI2CITransport.negativeAcknowledgment(statusCode: 3, message: "unsupported property operation"))
        }
    }

    private func encode(_ envelope: MIDI2CITransport.Envelope) -> [[UInt32]] {
        guard let words = try? MIDI2CITransport.encode(envelope) else { return [] }
        return [words]
    }
}
