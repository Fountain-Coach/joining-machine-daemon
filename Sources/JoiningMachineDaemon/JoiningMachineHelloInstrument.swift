import Foundation
import MIDI2CITransport
import MIDI2Transports

/// A dedicated MIDI-CI Discovery initiator for asking one remote instrument
/// to identify itself. It owns no responder state and writes no Store data.
public struct JoiningMachineHelloInstrument: Sendable {
    public struct Response: Codable, Equatable, Sendable {
        public let muid: UInt32
        public let softwareRevision: UInt32
        public let categories: [String]
        public let maxSysEx: UInt32
    }

    public enum Error: Swift.Error, Equatable {
        case timeout
        case invalidResponse
    }

    public let muid: UInt32
    public let softwareRevision: UInt32

    public init(muid: UInt32, softwareRevision: UInt32) {
        self.muid = muid
        self.softwareRevision = softwareRevision
    }

    public func ask(transport: any MIDITransport, timeout: TimeInterval = 10) async throws -> Response {
        let request = try MIDI2CITransport.encode(
            MIDI2CITransport.discovery(muid: muid, softwareRevision: softwareRevision))
        return try await withCheckedThrowingContinuation { continuation in
            let gate = HelloContinuationGate()
            transport.onReceiveUMP = { words in
                guard let envelope = MIDI2CITransport.decode(words: words),
                      case .discovery(let body) = envelope.body else { return }
                let categories = [
                    body.categories.profiles ? "profiles" : nil,
                    body.categories.propertyExchange ? "property-exchange" : nil,
                    body.categories.processInquiry ? "process-inquiry" : nil
                ].compactMap { $0 }
                gate.resume {
                    continuation.resume(returning: Response(
                        muid: body.muid, softwareRevision: body.softwareRev,
                        categories: categories, maxSysEx: body.maxSysEx))
                }
            }
            do {
                try transport.open()
                try transport.send(umpWords: request)
            } catch {
                gate.resume { continuation.resume(throwing: error) }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                gate.resume { continuation.resume(throwing: Error.timeout) }
            }
        }
    }
}

private final class HelloContinuationGate: @unchecked Sendable {
    private let lock = NSLock()
    private var completed = false

    func resume(_ action: () -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !completed else { return }
        completed = true
        action()
    }
}
