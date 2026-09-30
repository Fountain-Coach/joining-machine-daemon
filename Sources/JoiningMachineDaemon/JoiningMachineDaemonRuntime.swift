import Foundation
import MIDI2CITransport
import JoiningMachineTransportBoundary

/// Lifecycle states owned by the standalone joining-machine runtime. `ready` means the transport is open and the
/// daemon has answered at least one MIDI-CI discovery request; it does not mean Chapter 141 admission.
public enum JoiningMachineDaemonState: String, Codable, Equatable, Sendable {
    case stopped
    case starting
    case listening
    case ready
    case failed
}

public struct JoiningMachineDaemonLifecycle: Codable, Equatable, Sendable {
    public let state: JoiningMachineDaemonState
    public let generation: UInt64
    public let restartCount: UInt64
    public let endpoint: String
    public let detail: String?

    public init(state: JoiningMachineDaemonState, generation: UInt64, restartCount: UInt64,
                endpoint: String, detail: String? = nil) {
        self.state = state
        self.generation = generation
        self.restartCount = restartCount
        self.endpoint = endpoint
        self.detail = detail
    }
}

public enum JoiningMachineDaemonError: Error, Equatable, Sendable {
    case alreadyRunning
    case notRunning
    case invalidEndpoint
    case readinessPropertyMissing
    case invalidPropertyChunkSize
    case transportFailure
}

/// A small, supervisor-friendly daemon core. The host supplies the transport and responder; this type owns no
/// credentials, Store, filesystem, signing key, or remote-install policy. A service manager may restart the process,
/// while the generation/restart counters make that lifecycle observable to the owning host.
public final class JoiningMachineDaemonRuntime: @unchecked Sendable {
    public typealias LifecycleSink = @Sendable (JoiningMachineDaemonLifecycle) -> Void

    private let transport: any MIDITransport
    private let responder: MIDI2CIResponder
    private let endpoint: String
    private let sink: LifecycleSink?
    private let lock = NSLock()
    private var lifecycle: JoiningMachineDaemonLifecycle
    private var running = false

    public init(transport: any MIDITransport, responder: MIDI2CIResponder, endpoint: String,
                lifecycleSink: LifecycleSink? = nil) throws {
        guard endpoint.hasPrefix("midi2://") else { throw JoiningMachineDaemonError.invalidEndpoint }
        self.transport = transport
        self.responder = responder
        self.endpoint = endpoint
        self.sink = lifecycleSink
        self.lifecycle = JoiningMachineDaemonLifecycle(
            state: .stopped, generation: 0, restartCount: 0, endpoint: endpoint)
    }

    public var currentLifecycle: JoiningMachineDaemonLifecycle {
        lock.lock(); defer { lock.unlock() }
        return lifecycle
    }

    public func start() throws {
        lock.lock()
        guard !running else { lock.unlock(); throw JoiningMachineDaemonError.alreadyRunning }
        running = true
        let generation = lifecycle.generation + 1
        lifecycle = JoiningMachineDaemonLifecycle(
            state: .starting, generation: generation, restartCount: lifecycle.restartCount, endpoint: endpoint)
        let starting = lifecycle
        lock.unlock()
        sink?(starting)

        transport.onReceiveUMP = { [weak self] words in self?.receive(words: words) }
        do {
            try transport.open()
            update(state: .listening)
        } catch {
            lock.lock()
            running = false
            lifecycle = JoiningMachineDaemonLifecycle(
                state: .failed, generation: generation, restartCount: lifecycle.restartCount,
                endpoint: endpoint, detail: "transport-open-failed")
            let failed = lifecycle
            lock.unlock()
            sink?(failed)
            throw JoiningMachineDaemonError.transportFailure
        }
    }

    public func restart() throws {
        lock.lock()
        guard running else { lock.unlock(); throw JoiningMachineDaemonError.notRunning }
        lifecycle = JoiningMachineDaemonLifecycle(
            state: .stopped, generation: lifecycle.generation, restartCount: lifecycle.restartCount + 1,
            endpoint: endpoint, detail: "restart")
        let stopped = lifecycle
        running = false
        lock.unlock()
        sink?(stopped)
        try? transport.close()
        try start()
    }

    public func stop() throws {
        lock.lock()
        guard running else { lock.unlock(); throw JoiningMachineDaemonError.notRunning }
        running = false
        lifecycle = JoiningMachineDaemonLifecycle(
            state: .stopped, generation: lifecycle.generation, restartCount: lifecycle.restartCount,
            endpoint: endpoint)
        let stopped = lifecycle
        lock.unlock()
        transport.onReceiveUMP = nil
        try transport.close()
        sink?(stopped)
    }

    private func receive(words: [UInt32]) {
        lock.lock()
        let acceptsRequest = running && lifecycle.state != .failed
        lock.unlock()
        guard acceptsRequest else { return }
        let replies = responder.receive(words: words)
        guard !replies.isEmpty else { return }
        for reply in replies {
            do { try transport.send(umpWords: reply) }
            catch {
                update(state: .failed, detail: "transport-send-failed")
                return
            }
        }
        if MIDI2CITransport.decode(words: words).map({
            if case .discovery = $0.body { return true }; return false
        }) == true {
            update(state: .ready)
        }
    }

    private func update(state: JoiningMachineDaemonState, detail: String? = nil) {
        lock.lock()
        lifecycle = JoiningMachineDaemonLifecycle(
            state: state, generation: lifecycle.generation, restartCount: lifecycle.restartCount,
            endpoint: endpoint, detail: detail)
        let value = lifecycle
        lock.unlock()
        sink?(value)
    }
}
