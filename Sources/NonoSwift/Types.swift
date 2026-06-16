import Foundation

public struct AccessMode: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let read = AccessMode(rawValue: 0)
    public static let write = AccessMode(rawValue: 1)
    public static let readWrite = AccessMode(rawValue: 2)

    public var description: String {
        switch rawValue {
        case Self.read.rawValue:
            return "read"
        case Self.write.rawValue:
            return "write"
        case Self.readWrite.rawValue:
            return "read-write"
        default:
            return "AccessMode(\(rawValue))"
        }
    }
}

public struct NetworkMode: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let blocked = NetworkMode(rawValue: 0)
    public static let allowAll = NetworkMode(rawValue: 1)
    public static let proxyOnly = NetworkMode(rawValue: 2)

    public var description: String {
        switch rawValue {
        case Self.blocked.rawValue:
            return "blocked"
        case Self.allowAll.rawValue:
            return "allow-all"
        case Self.proxyOnly.rawValue:
            return "proxy-only"
        default:
            return "NetworkMode(\(rawValue))"
        }
    }
}

public struct CapabilitySource: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    public let rawValue: Int32

    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }

    public static let user = CapabilitySource(rawValue: 0)
    public static let group = CapabilitySource(rawValue: 1)
    public static let system = CapabilitySource(rawValue: 2)
    public static let profile = CapabilitySource(rawValue: 3)

    public var description: String {
        switch rawValue {
        case Self.user.rawValue:
            return "user"
        case Self.group.rawValue:
            return "group"
        case Self.system.rawValue:
            return "system"
        case Self.profile.rawValue:
            return "profile"
        default:
            return "CapabilitySource(\(rawValue))"
        }
    }
}

public struct QueryStatus: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let allowed = QueryStatus(rawValue: 0)
    public static let denied = QueryStatus(rawValue: 1)

    public var description: String {
        switch rawValue {
        case Self.allowed.rawValue:
            return "allowed"
        case Self.denied.rawValue:
            return "denied"
        default:
            return "QueryStatus(\(rawValue))"
        }
    }
}

public struct QueryReason: RawRepresentable, Sendable, Hashable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let grantedPath = QueryReason(rawValue: 0)
    public static let networkAllowed = QueryReason(rawValue: 1)
    public static let pathNotGranted = QueryReason(rawValue: 2)
    public static let insufficientAccess = QueryReason(rawValue: 3)
    public static let networkBlocked = QueryReason(rawValue: 4)

    public var description: String {
        switch rawValue {
        case Self.grantedPath.rawValue:
            return "granted-path"
        case Self.networkAllowed.rawValue:
            return "network-allowed"
        case Self.pathNotGranted.rawValue:
            return "path-not-granted"
        case Self.insufficientAccess.rawValue:
            return "insufficient-access"
        case Self.networkBlocked.rawValue:
            return "network-blocked"
        default:
            return "QueryReason(\(rawValue))"
        }
    }
}

public struct FileSystemCapability: Sendable, Hashable {
    public let originalPath: String
    public let resolvedPath: String
    public let access: AccessMode
    public let isFile: Bool
    public let source: CapabilitySource
    public let groupName: String

    public init(
        originalPath: String,
        resolvedPath: String,
        access: AccessMode,
        isFile: Bool,
        source: CapabilitySource,
        groupName: String
    ) {
        self.originalPath = originalPath
        self.resolvedPath = resolvedPath
        self.access = access
        self.isFile = isFile
        self.source = source
        self.groupName = groupName
    }
}

public struct QueryResult: Sendable, Hashable {
    public let status: QueryStatus
    public let reason: QueryReason
    public let grantedPath: String
    public let grantedAccess: String
    public let actualAccess: String
    public let requestedAccess: String

    public init(
        status: QueryStatus,
        reason: QueryReason,
        grantedPath: String,
        grantedAccess: String,
        actualAccess: String,
        requestedAccess: String
    ) {
        self.status = status
        self.reason = reason
        self.grantedPath = grantedPath
        self.grantedAccess = grantedAccess
        self.actualAccess = actualAccess
        self.requestedAccess = requestedAccess
    }
}

public struct PlatformInfo: Sendable, Hashable {
    public let isSupported: Bool
    public let platform: String
    public let details: String

    public init(isSupported: Bool, platform: String, details: String) {
        self.isSupported = isSupported
        self.platform = platform
        self.details = details
    }
}
