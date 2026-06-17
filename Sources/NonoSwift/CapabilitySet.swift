import CNono
import Foundation

public final class CapabilitySet: @unchecked Sendable {
    internal static let closedMessage = "capability set is closed"

    internal let lock = NSLock()
    internal var pointer: OpaquePointer?

    public init() {
        guard let pointer = nono_capability_set_new() else {
            fatalError("nono: nono_capability_set_new returned nil")
        }
        self.pointer = pointer
    }

    internal init(taking pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        close()
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }

        if let pointer {
            nono_capability_set_free(pointer)
            self.pointer = nil
        }
    }

    public func allowPath(_ path: String, access: AccessMode) throws {
        try checkNoNUL(path)
        try withOpenPointer { pointer in
            let code = path.withCString { cPath in
                nono_capability_set_allow_path(pointer, cPath, access.rawValue)
            }
            try throwIfError(code)
        }
    }

    public func allowFile(_ path: String, access: AccessMode) throws {
        try checkNoNUL(path)
        try withOpenPointer { pointer in
            let code = path.withCString { cPath in
                nono_capability_set_allow_file(pointer, cPath, access.rawValue)
            }
            try throwIfError(code)
        }
    }

    public func setNetworkMode(_ mode: NetworkMode) throws {
        try withOpenPointer { pointer in
            try throwIfError(nono_capability_set_set_network_mode(pointer, mode.rawValue))
        }
    }

    public func blockNetwork() throws {
        try setNetworkMode(.blocked)
    }

    public var networkMode: NetworkMode {
        lock.lock()
        defer { lock.unlock() }

        guard let pointer else { return .blocked }
        return NetworkMode(rawValue: nono_capability_set_network_mode(pointer))
    }

    public func setProxyPort(_ port: UInt16) throws {
        try withOpenPointer { pointer in
            try throwIfError(nono_capability_set_set_proxy_port(pointer, port))
        }
    }

    public var proxyPort: UInt16 {
        lock.lock()
        defer { lock.unlock() }

        guard let pointer else { return 0 }
        return nono_capability_set_proxy_port(pointer)
    }

    public func addPlatformRule(_ rule: String) throws {
        try checkNoNUL(rule)
        try withOpenPointer { pointer in
            let code = rule.withCString { cRule in
                nono_capability_set_add_platform_rule(pointer, cRule)
            }
            try throwIfError(code)
        }
    }

    public func deduplicate() throws {
        try withOpenPointer { pointer in
            nono_capability_set_deduplicate(pointer)
        }
    }

    public func pathCovered(_ path: String) throws -> Bool {
        try checkNoNUL(path)

        lock.lock()
        defer { lock.unlock() }

        guard let pointer else { return false }
        return path.withCString { cPath in
            nono_capability_set_path_covered(pointer, cPath)
        }
    }

    public var isNetworkBlocked: Bool {
        lock.lock()
        defer { lock.unlock() }

        guard let pointer else { return false }
        return nono_capability_set_is_network_blocked(pointer)
    }

    public var summary: String {
        lock.lock()
        defer { lock.unlock() }

        guard let pointer else { return "" }
        return copyAndFreeCString(nono_capability_set_summary(pointer))
    }

    public var fileSystemCapabilities: [FileSystemCapability] {
        lock.lock()
        defer { lock.unlock() }

        guard let pointer else { return [] }

        let count = Int(nono_capability_set_fs_count(pointer))
        var capabilities: [FileSystemCapability] = []
        capabilities.reserveCapacity(count)

        for index in 0..<count {
            let cIndex = UInt(index)
            let accessRaw = nono_capability_set_fs_access(pointer, cIndex)
            guard accessRaw != UInt32.max else { continue }

            let sourceRaw = nono_capability_set_fs_source_tag(pointer, cIndex).rawValue
            capabilities.append(FileSystemCapability(
                originalPath: copyAndFreeCString(nono_capability_set_fs_original(pointer, cIndex)),
                resolvedPath: copyAndFreeCString(nono_capability_set_fs_resolved(pointer, cIndex)),
                access: AccessMode(rawValue: accessRaw),
                isFile: nono_capability_set_fs_is_file(pointer, cIndex),
                source: CapabilitySource(rawValue: Int32(sourceRaw)),
                groupName: copyAndFreeCString(nono_capability_set_fs_source_group_name(pointer, cIndex))
            ))
        }

        return capabilities
    }

    internal func withOpenPointer<T>(_ body: (OpaquePointer) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }

        guard let pointer else {
            throw staticError(.invalidArgument, Self.closedMessage)
        }

        return try body(pointer)
    }
}
