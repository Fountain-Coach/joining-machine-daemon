import Foundation

/// Reads the target-owned readiness projection used by the live daemon.
public struct JoiningMachineDaemonReadinessFileProvider: JoiningMachineDaemonReadinessPropertyProvider, Sendable {
    public let path: String

    public init(path: String) throws {
        guard path.hasPrefix("/"), !path.contains("\0") else {
            throw JoiningMachineDaemonReadinessFileError.invalidPath
        }
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
    }

    public func readinessPropertyData() async throws -> Data {
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw JoiningMachineDaemonReadinessFileError.notARegularFile
        }
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard !data.isEmpty else { throw JoiningMachineDaemonReadinessFileError.empty }
        return data
    }
}

public enum JoiningMachineDaemonReadinessFileError: Error, Equatable, Sendable {
    case invalidPath
    case notARegularFile
    case empty
}
