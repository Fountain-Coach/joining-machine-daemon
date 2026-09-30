import Foundation

public protocol MIDITransport: AnyObject, Sendable {
    func open() throws
    func close() throws
    func send(umpWords: [UInt32]) throws
    var onReceiveUMP: (([UInt32]) -> Void)? { get set }
}
