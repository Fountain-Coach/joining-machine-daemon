import Foundation
import MIDI2Transports

/// Store/host boundary for the joining-machine daemon. The provider is the
/// authority for the already-signed readiness property; this adapter owns only
/// composition and daemon lifecycle.
public protocol JoiningMachineDaemonReadinessPropertyProvider: Sendable {
    func readinessPropertyData() async throws -> Data
}

public enum JoiningMachineDaemonHostAdapterError: Error, Equatable, Sendable {
    case alreadyStarted
    case notStarted
}

/// Composes one Store-derived readiness property with the existing native
/// MIDI2-CI responder and restart-safe runtime. It never reads a sidecar file,
/// creates an identity, or installs an artifact.
public final class JoiningMachineDaemonHostAdapter: @unchecked Sendable {
    private let muid: UInt32
    private let softwareRevision: UInt32
    private let endpoint: String
    private let maxDataPerMessage: Int
    private let provider: any JoiningMachineDaemonReadinessPropertyProvider
    private let transport: any MIDITransport
    private let lifecycleSink: JoiningMachineDaemonRuntime.LifecycleSink?
    private let lock = NSLock()
    private var runtime: JoiningMachineDaemonRuntime?
    private var startInProgress = false

    public init(
        muid: UInt32,
        softwareRevision: UInt32,
        endpoint: String,
        maxDataPerMessage: Int = 80,
        provider: any JoiningMachineDaemonReadinessPropertyProvider,
        transport: any MIDITransport,
        lifecycleSink: JoiningMachineDaemonRuntime.LifecycleSink? = nil
    ) {
        self.muid = muid
        self.softwareRevision = softwareRevision
        self.endpoint = endpoint
        self.maxDataPerMessage = maxDataPerMessage
        self.provider = provider
        self.transport = transport
        self.lifecycleSink = lifecycleSink
    }

    public convenience init(
        identity: JoiningMachineInstrumentIdentity,
        endpoint: String,
        maxDataPerMessage: Int = 80,
        provider: any JoiningMachineDaemonReadinessPropertyProvider,
        transport: any MIDITransport,
        lifecycleSink: JoiningMachineDaemonRuntime.LifecycleSink? = nil
    ) {
        self.init(muid: identity.muid, softwareRevision: identity.softwareRevision,
                  endpoint: endpoint, maxDataPerMessage: maxDataPerMessage,
                  provider: provider, transport: transport, lifecycleSink: lifecycleSink)
    }

    public func start() async throws -> JoiningMachineDaemonLifecycle {
        try beginStart()
        do {
            let readiness = try await provider.readinessPropertyData()
            let configuration = try JoiningMachineDaemonInstrumentConfiguration(
                muid: muid,
                softwareRevision: softwareRevision,
                endpoint: endpoint,
                readinessPropertyData: readiness,
                maxDataPerMessage: maxDataPerMessage)
            let created = try configuration.makeRuntime(transport: transport, lifecycleSink: lifecycleSink)
            try created.start()
            finishStart(with: created)
            return created.currentLifecycle
        } catch {
            finishStart(with: nil)
            throw error
        }
    }

    private func beginStart() throws {
        lock.lock()
        defer { lock.unlock() }
        guard runtime == nil, !startInProgress else {
            throw JoiningMachineDaemonHostAdapterError.alreadyStarted
        }
        startInProgress = true
    }

    private func finishStart(with runtime: JoiningMachineDaemonRuntime?) {
        lock.lock()
        self.runtime = runtime
        startInProgress = false
        lock.unlock()
    }

    public func restart() throws -> JoiningMachineDaemonLifecycle {
        lock.lock()
        guard let runtime else {
            lock.unlock()
            throw JoiningMachineDaemonHostAdapterError.notStarted
        }
        lock.unlock()
        try runtime.restart()
        return runtime.currentLifecycle
    }

    public func stop() throws -> JoiningMachineDaemonLifecycle {
        lock.lock()
        guard let runtime else {
            lock.unlock()
            throw JoiningMachineDaemonHostAdapterError.notStarted
        }
        lock.unlock()
        try runtime.stop()
        let lifecycle = runtime.currentLifecycle
        lock.lock()
        self.runtime = nil
        lock.unlock()
        return lifecycle
    }

    public var currentLifecycle: JoiningMachineDaemonLifecycle? {
        lock.lock(); defer { lock.unlock() }
        return runtime?.currentLifecycle
    }
}
