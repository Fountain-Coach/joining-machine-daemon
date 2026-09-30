import XCTest
@testable import JoiningMachineDaemon

final class JoiningMachineDaemonTests: XCTestCase {
    func testHostManifestIsDeterministicAndRedacted() throws {
        let manifest = try JoiningMachineInstrumentHostManifest.reference(
            platform: "Linux", transport: "RTP-MIDI2",
            supportedTransports: ["RTP-MIDI2", "Network-MIDI2-UDP"])
        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(JoiningMachineInstrumentHostManifest.self, from: data)
        XCTAssertEqual(decoded, manifest)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("secret"))
    }

    func testIdentityRejectsZeroValues() {
        XCTAssertThrowsError(try JoiningMachineInstrumentIdentity(muid: 0, softwareRevision: 1))
        XCTAssertThrowsError(try JoiningMachineInstrumentIdentity(muid: 1, softwareRevision: 0))
    }

    func testReadinessFileProviderReadsOnlyAbsoluteRegularFiles() async throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("joining-machine-readiness-(UUID().uuidString)")
        try Data("typed-readiness".utf8).write(to: path, options: .atomic)
        defer { try? FileManager.default.removeItem(at: path) }

        let provider = try JoiningMachineDaemonReadinessFileProvider(path: path.path)
        let readiness = try await provider.readinessPropertyData()
        XCTAssertEqual(readiness, Data("typed-readiness".utf8))
        XCTAssertThrowsError(try JoiningMachineDaemonReadinessFileProvider(path: "relative/readiness")) { error in
            XCTAssertEqual(error as? JoiningMachineDaemonReadinessFileError, .invalidPath)
        }
    }
}
