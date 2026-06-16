import CNono
import Foundation

public final class SandboxState: @unchecked Sendable {
    private static let closedMessage = "sandbox state is closed"

    private let lock = NSLock()
    private var pointer: OpaquePointer?

    public init(capabilities: CapabilitySet) throws {
        capabilities.lock.lock()
        defer { capabilities.lock.unlock() }

        guard let capabilityPointer = capabilities.pointer else {
            throw staticError(.invalidArgument, CapabilitySet.closedMessage)
        }

        guard let pointer = nono_sandbox_state_from_caps(capabilityPointer) else {
            throw staticError(.unknown, "failed to create sandbox state")
        }

        self.pointer = pointer
    }

    public init(json: String) throws {
        try checkNoNUL(json)

        let pointer = json.withCString { cJSON in
            nono_sandbox_state_from_json(cJSON)
        }

        guard let pointer else {
            throw mapError(rawCode: NonoError.Code.unknown.rawValue)
        }

        self.pointer = pointer
    }

    deinit {
        close()
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }

        if let pointer {
            nono_sandbox_state_free(pointer)
            self.pointer = nil
        }
    }

    public func json() throws -> String {
        try withOpenPointer { pointer in
            guard let cJSON = nono_sandbox_state_to_json(pointer) else {
                throw mapError(rawCode: NonoError.Code.unknown.rawValue)
            }
            return copyAndFreeCString(cJSON)
        }
    }

    public func capabilities() throws -> CapabilitySet {
        try withOpenPointer { pointer in
            guard let capabilityPointer = nono_sandbox_state_to_caps(pointer) else {
                throw mapError(rawCode: NonoError.Code.unknown.rawValue)
            }
            return CapabilitySet(taking: capabilityPointer)
        }
    }

    private func withOpenPointer<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        guard let pointer else {
            throw staticError(.invalidArgument, Self.closedMessage)
        }

        return try body(pointer)
    }
}
