import CNono
import Foundation

public func apply(_ capabilities: CapabilitySet) throws {
    capabilities.lock.lock()
    defer { capabilities.lock.unlock() }

    guard let pointer = capabilities.pointer else {
        throw staticError(.invalidArgument, CapabilitySet.closedMessage)
    }

    let code = nono_sandbox_apply(pointer)
    try throwIfError(code)

    nono_capability_set_free(pointer)
    capabilities.pointer = nil
}

public var isSupported: Bool {
    nono_sandbox_is_supported()
}

public func supportInfo() -> PlatformInfo {
    let info = nono_sandbox_support_info()
    return PlatformInfo(
        isSupported: info.is_supported,
        platform: copyAndFreeCString(info.platform),
        details: copyAndFreeCString(info.details)
    )
}

public var version: String {
    copyAndFreeCString(nono_version())
}
