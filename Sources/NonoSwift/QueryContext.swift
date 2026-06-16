import CNono
import Foundation

public final class QueryContext: @unchecked Sendable {
    private static let closedMessage = "query context is closed"

    private let lock = NSLock()
    private var pointer: OpaquePointer?

    public init(capabilities: CapabilitySet) throws {
        capabilities.lock.lock()
        defer { capabilities.lock.unlock() }

        guard let capabilityPointer = capabilities.pointer else {
            throw staticError(.invalidArgument, CapabilitySet.closedMessage)
        }

        guard let pointer = nono_query_context_new(capabilityPointer) else {
            throw staticError(.unknown, "failed to create query context")
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
            nono_query_context_free(pointer)
            self.pointer = nil
        }
    }

    public func queryPath(_ path: String, access: AccessMode) throws -> QueryResult {
        try checkNoNUL(path)

        return try withOpenPointer { pointer in
            var cResult = NonoQueryResult()
            let code = path.withCString { cPath in
                nono_query_context_query_path(pointer, cPath, access.rawValue, &cResult)
            }
            try throwIfError(code)
            return extractQueryResult(cResult)
        }
    }

    public func queryNetwork() throws -> QueryResult {
        try withOpenPointer { pointer in
            var cResult = NonoQueryResult()
            let code = nono_query_context_query_network(pointer, &cResult)
            try throwIfError(code)
            return extractQueryResult(cResult)
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

private func extractQueryResult(_ result: NonoQueryResult) -> QueryResult {
    QueryResult(
        status: QueryStatus(rawValue: result.status.rawValue),
        reason: QueryReason(rawValue: result.reason.rawValue),
        grantedPath: copyAndFreeCString(result.granted_path),
        grantedAccess: copyAndFreeCString(result.access),
        actualAccess: copyAndFreeCString(result.granted),
        requestedAccess: copyAndFreeCString(result.requested)
    )
}
