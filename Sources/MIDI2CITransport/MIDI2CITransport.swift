import Foundation
import MIDI2
import MIDI2CI

/// Repository-native standard MIDI-CI over UMP/SysEx8.
///
/// Fountain Coach adds its typed property payload only after this exchange. This adapter does not reinterpret
/// MIDI-CI fields or introduce a parallel discovery protocol.
public enum MIDI2CITransport {
    public typealias Envelope = MidiCiEnvelope
    public typealias PropertyExchangeBody = MidiCiPropertyExchangeBody
    public typealias ProfilesBody = MidiCiProfilesBody
    public typealias ProcessInquiryBody = MidiCiProcessInquiryBody
    public typealias PropertyEncoding = MidiCiPropertyExchangeBody.Encoding
    public static let universalNonRealtimeManufacturerID: [UInt8] = [0x7E]

    public static func encode(_ envelope: MidiCiEnvelope, group: UInt8 = 0) throws -> [UInt32] {
        guard let umpGroup = Uint4(group) else { throw Error.invalidGroup }
        let body = try DataMessageBody.sysex8(
            manufacturerID: universalNonRealtimeManufacturerID,
            data: envelope.sysEx8Payload()).umpPackets(group: umpGroup)
        return body.flatMap(\.words)
    }

    public static func decode(words: [UInt32]) -> MidiCiEnvelope? {
        guard words.count.isMultiple(of: 4) else { return nil }
        let packets = stride(from: 0, to: words.count, by: 4).compactMap { index -> UmpPacket128? in
            UmpPacket128(words: Array(words[index..<(index + 4)]))
        }
        guard packets.count == words.count / 4,
              let body = DataMessageBody(sysex8Packets: packets),
              case let .sysex8(manufacturerID, payload) = body,
              manufacturerID == universalNonRealtimeManufacturerID else { return nil }
        return try? MidiCiEnvelope(sysEx8Payload: payload)
    }

    public static func discovery(muid: UInt32, softwareRevision: UInt32, maxSysEx: UInt32 = 2048) -> MidiCiEnvelope {
        MidiCiEnvelope(
            scope: .nonRealtime,
            subId2: 0x70,
            version: 1,
            body: .discovery(MidiCiDiscoveryBody(
                muid: muid,
                manufacturerId: [0x00, 0x7D, 0x00],
                deviceFamily: 0x4643,
                deviceModel: 0x0001,
                softwareRev: softwareRevision,
                categories: .init(profiles: true, propertyExchange: true, processInquiry: true),
                maxSysEx: maxSysEx)))
    }

    public static func profileInquiry(profileID: String) -> MidiCiEnvelope {
        MidiCiEnvelope(scope: .nonRealtime, subId2: 0x72, body: .profiles(
            MidiCiProfilesBody(command: .inquiry, profileId: profileID, target: .functionBlock)))
    }

    public static func profileReply(for inquiry: MidiCiProfilesBody, supported: Bool) -> MidiCiEnvelope {
        MidiCiEnvelope(scope: .nonRealtime, subId2: 0x72, body: .profiles(
            MidiCiProfilesBody(command: .reply,
                              profileId: inquiry.profileId, target: inquiry.target, channels: inquiry.channels,
                              details: ["ver": 1, "supported": supported ? 1 : 0, "enabled": 0, "psd": 0])))
    }

    public static func profileSetOn(profileID: String, target: MidiCiProfilesBody.Target = .functionBlock) -> MidiCiEnvelope {
        profileConfiguration(.setOn, profileID: profileID, target: target)
    }

    public static func profileSetOff(profileID: String, target: MidiCiProfilesBody.Target = .functionBlock) -> MidiCiEnvelope {
        profileConfiguration(.setOff, profileID: profileID, target: target)
    }

    public static func profileDetailsInquiry(profileID: String, target: MidiCiProfilesBody.Target = .functionBlock) -> MidiCiEnvelope {
        profileConfiguration(.detailsInquiry, profileID: profileID, target: target)
    }

    private static func profileConfiguration(_ command: MidiCiProfilesBody.Command,
                                             profileID: String,
                                             target: MidiCiProfilesBody.Target) -> MidiCiEnvelope {
        MidiCiEnvelope(scope: .nonRealtime, subId2: 0x72, body: .profiles(
            MidiCiProfilesBody(command: command, profileId: profileID, target: target)))
    }

    public static func propertyGet(resource: String, requestID: UInt32) -> MidiCiEnvelope {
        MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, body: .propertyExchange(
            PropertyExchangeBuilder.makeGet(resource: resource, requestId: requestID)))
    }

    public static func propertyGetReply(resource: String, requestID: UInt32, data: [UInt8]) -> MidiCiEnvelope {
        propertyGetReplies(resource: resource, requestID: requestID, data: data).first!
    }

    public static func propertyGetReplies(resource: String,
                                          requestID: UInt32,
                                          data: [UInt8],
                                          encoding: PropertyEncoding = .json,
                                          maxDataPerMessage: Int = 80) -> [MidiCiEnvelope] {
        let bodies = data.isEmpty
            ? [MidiCiPropertyExchangeBody(command: .getReply, requestId: requestID, encoding: encoding,
                                          header: ["res": resource, "total": "0", "offset": "0", "length": "0", "more": "0"], data: [])]
            : PropertyExchangeChunker.chunkGetReply(
                resource: resource, requestId: requestID, encoding: encoding,
                data: data, maxDataPerMessage: maxDataPerMessage)
        return bodies.map { MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7C, body: .propertyExchange($0)) }
    }

    public static func encodeProperty(_ data: [UInt8], using encoding: PropertyEncoding) -> [UInt8] {
        PropertyExchangeCodec.encode(data, using: encoding)
    }

    public static func decodeProperty(_ data: [UInt8], using encoding: PropertyEncoding) -> [UInt8] {
        PropertyExchangeCodec.decode(data, using: encoding)
    }

    public static func processInquiry() -> MidiCiEnvelope {
        MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7E, body: .processInquiry(
            MidiCiProcessInquiryBody(command: .capInquiry)))
    }

    public static func processInquiryReply(filters: [String: UInt8] = [:]) -> MidiCiEnvelope {
        MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7E, body: .processInquiry(
            MidiCiProcessInquiryBody(command: .capReply, filters: filters.isEmpty ? nil : filters)))
    }

    public static func processMessageReport(filters: [String: UInt8] = [:]) -> MidiCiEnvelope {
        MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7E, body: .processInquiry(
            MidiCiProcessInquiryBody(command: .messageReport, filters: filters.isEmpty ? nil : filters)))
    }

    public static func processMessageReportReply(filters: [String: UInt8] = [:]) -> MidiCiEnvelope {
        MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7E, body: .processInquiry(
            MidiCiProcessInquiryBody(command: .messageReportReply, filters: filters.isEmpty ? nil : filters)))
    }

    public static func processEndReport() -> MidiCiEnvelope {
        MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7E, body: .processInquiry(
            MidiCiProcessInquiryBody(command: .endReport)))
    }

    public static func acknowledgment(statusCode: UInt8 = 0, message: String = "accepted") -> MidiCiEnvelope {
        MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7F, body: .ackNak(
            MidiCiAckNakBody(ack: true, statusCode: statusCode, message: message)))
    }

    public static func negativeAcknowledgment(statusCode: UInt8, message: String) -> MidiCiEnvelope {
        MidiCiEnvelope(scope: .nonRealtime, subId2: 0x7F, body: .ackNak(
            MidiCiAckNakBody(ack: false, statusCode: statusCode, message: message)))
    }

    public enum Error: Swift.Error, Equatable { case invalidGroup }
}
