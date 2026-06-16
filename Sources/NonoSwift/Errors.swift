import CNono
import Foundation

public struct NonoError: Error, Sendable, Hashable, CustomStringConvertible, LocalizedError {
    public enum Code: Int32, Sendable, Hashable {
        case pathNotFound = -1
        case expectedDirectory = -2
        case expectedFile = -3
        case pathCanonicalization = -4
        case noCapabilities = -5
        case sandboxInit = -6
        case unsupportedPlatform = -7
        case blockedCommand = -8
        case configParse = -9
        case profileParse = -10
        case io = -11
        case invalidArgument = -12
        case trustVerification = -13
        case unknown = -99

        internal static func fromRawValue(_ rawValue: Int32) -> Code {
            Code(rawValue: rawValue) ?? .unknown
        }
    }

    public let code: Code
    public let message: String

    public init(code: Code, message: String) {
        self.code = code
        self.message = message
    }

    public var description: String {
        if message.isEmpty {
            return "nono error \(code.rawValue)"
        }
        return message
    }

    public var errorDescription: String? {
        description
    }
}

@inline(__always)
internal func isOK(_ code: NonoErrorCode) -> Bool {
    code.rawValue == 0
}

internal func throwIfError(_ code: NonoErrorCode) throws {
    guard !isOK(code) else { return }
    throw mapError(rawCode: code.rawValue)
}

internal func mapError(rawCode: Int32) -> NonoError {
    let message = copyAndFreeCString(nono_last_error())
    nono_clear_error()
    return NonoError(
        code: .fromRawValue(rawCode),
        message: message.isEmpty ? "unknown error" : message
    )
}

internal func staticError(_ code: NonoError.Code, _ message: String) -> NonoError {
    NonoError(code: code, message: message)
}

internal func checkNoNUL(_ string: String) throws {
    if string.utf8.contains(0) {
        throw staticError(.invalidArgument, "string contains NUL byte")
    }
}

internal func copyAndFreeCString(_ pointer: UnsafeMutablePointer<CChar>?) -> String {
    guard let pointer else { return "" }
    defer { nono_string_free(pointer) }
    return String(cString: pointer)
}
