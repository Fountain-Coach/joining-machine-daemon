import Foundation
import JoiningMachineDaemon
import MIDI2Transports

private struct Arguments {
    let muid: UInt32
    let softwareRevision: UInt32
    let endpoint: String
    let readiness: Data
    let listenPort: UInt16
    let selfTest: Bool

    init() throws {
        let values = Array(CommandLine.arguments.dropFirst())
        func required(_ flag: String) throws -> String {
            guard let index = values.firstIndex(of: flag), index + 1 < values.count else {
                throw NSError(domain: "JoiningMachineDaemon", code: 64,
                              userInfo: [NSLocalizedDescriptionKey: "missing (flag)"])
            }
            return values[index + 1]
        }
        guard let muid = UInt32(try required("--muid")), muid != 0,
              let softwareRevision = UInt32(try required("--software-revision")), softwareRevision != 0,
              let listenPort = UInt16(values.firstIndex(of: "--listen-port").flatMap {
                  $0 + 1 < values.count ? values[$0 + 1] : nil
              } ?? "5004"), listenPort != 0,
              let readiness = Data(base64Encoded: try required("--readiness-base64")) else {
            throw NSError(domain: "JoiningMachineDaemon", code: 64,
                          userInfo: [NSLocalizedDescriptionKey: "invalid typed daemon input"])
        }
        let endpoint = try required("--endpoint")
        guard endpoint.hasPrefix("midi2://") else {
            throw NSError(domain: "JoiningMachineDaemon", code: 64,
                          userInfo: [NSLocalizedDescriptionKey: "endpoint must use midi2://"])
        }
        self.muid = muid
        self.softwareRevision = softwareRevision
        self.endpoint = endpoint
        self.readiness = readiness
        self.listenPort = listenPort
        self.selfTest = values.contains("--self-test")
    }
}

private struct StaticReadinessProvider: JoiningMachineDaemonReadinessPropertyProvider {
    let value: Data
    func readinessPropertyData() async throws -> Data { value }
}

@main
struct JoiningMachineDaemonExecutable {
    static func main() async {
        do {
            let arguments = try Arguments()
            let configuration = try JoiningMachineDaemonInstrumentConfiguration(
                muid: arguments.muid, softwareRevision: arguments.softwareRevision,
                endpoint: arguments.endpoint, readinessPropertyData: arguments.readiness)
            if arguments.selfTest {
                let report = try JoiningMachineDaemonSelfTest.run(configuration: configuration)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(report), as: UTF8.self))
                return
            }
            let transport = RTPMidiSession(localName: "Fountain Coach Joining Machine",
                                           enableDiscovery: false, listenPort: arguments.listenPort)
            let adapter = JoiningMachineDaemonHostAdapter(
                muid: arguments.muid, softwareRevision: arguments.softwareRevision,
                endpoint: arguments.endpoint, provider: StaticReadinessProvider(value: arguments.readiness),
                transport: transport) { lifecycle in
                    print("joining-machine-lifecycle=\(lifecycle.state.rawValue) generation=\(lifecycle.generation) restart_count=\(lifecycle.restartCount)")
                }
            let lifecycle = try await adapter.start()
            print("joining-machine-state=\(lifecycle.state.rawValue) admission=unestablished")
            while true { try await Task.sleep(for: .seconds(3600)) }
        } catch {
            FileHandle.standardError.write(Data("joining-machine: \(error.localizedDescription)\n".utf8))
            Foundation.exit(64)
        }
    }
}
