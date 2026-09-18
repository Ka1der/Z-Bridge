import Foundation

/// Поддерживаемые команды FTP протокола (RFC 959, RFC 2428)
public enum FTPCommand: Sendable {
    case user(String)
    case pass(String)
    case syst
    case feat
    case pwd
    case cwd(String)
    case cdup
    case type(String)
    case pasv
    case epsv
    case port(String)
    case eprt(String)
    case stor(String)
    case retr(String)
    case dele(String)
    case mkd(String)
    case rmd(String)
    case size(String)
    case mdtm(String)
    case rest(Int64)
    case auth(String)
    case noop
    case quit
    case unknown(String)
    
    /// Безопасное строковое представление команды для логирования (пароли маскируются)
    public var logDescription: String {
        switch self {
        case .user(let user): return "USER \(user)"
        case .pass: return "PASS ********"
        case .syst: return "SYST"
        case .feat: return "FEAT"
        case .pwd: return "PWD"
        case .cwd(let dir): return "CWD \(dir)"
        case .cdup: return "CDUP"
        case .type(let t): return "TYPE \(t)"
        case .pasv: return "PASV"
        case .epsv: return "EPSV"
        case .port(let p): return "PORT \(p)"
        case .eprt(let p): return "EPRT \(p)"
        case .stor(let f): return "STOR \(f)"
        case .retr(let f): return "RETR \(f)"
        case .dele(let f): return "DELE \(f)"
        case .mkd(let d): return "MKD \(d)"
        case .rmd(let d): return "RMD \(d)"
        case .size(let f): return "SIZE \(f)"
        case .mdtm(let f): return "MDTM \(f)"
        case .rest(let offset): return "REST \(offset)"
        case .auth(let mechanism): return "AUTH \(mechanism)"
        case .noop: return "NOOP"
        case .quit: return "QUIT"
        case .unknown(let cmd): return "UNKNOWN (\(cmd))"
        }
    }
    
    /// Парсинг сырой командной строки FTP
    public static func parse(_ line: String) -> FTPCommand {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .noop }
        
        let parts = trimmed.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        let verb = parts[0].uppercased()
        let argument = parts.count > 1 ? String(parts[1]) : ""
        
        switch verb {
        case "USER": return .user(argument)
        case "PASS": return .pass(argument)
        case "SYST": return .syst
        case "FEAT": return .feat
        case "PWD", "XPWD": return .pwd
        case "CWD", "XCWD": return .cwd(argument)
        case "CDUP", "XCUP": return .cdup
        case "TYPE": return .type(argument.uppercased())
        case "PASV": return .pasv
        case "EPSV": return .epsv
        case "PORT": return .port(argument)
        case "EPRT": return .eprt(argument)
        case "STOR": return .stor(argument)
        case "RETR": return .retr(argument)
        case "DELE": return .dele(argument)
        case "MKD", "XMKD": return .mkd(argument)
        case "RMD", "XRMD": return .rmd(argument)
        case "SIZE": return .size(argument)
        case "MDTM": return .mdtm(argument)
        case "REST": return .rest(Int64(argument) ?? 0)
        case "AUTH": return .auth(argument)
        case "NOOP": return .noop
        case "QUIT": return .quit
        default: return .unknown(verb)
        }
    }
}

/// Стандартные ответы FTP протокола
public struct FTPResponse: Sendable {
    public let code: Int
    public let message: String
    
    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
    
    public var formatted: String {
        "\(code) \(message)\r\n"
    }
    
    public static let banner = FTPResponse(code: 220, message: "NikonZbridge High-Speed Ingest Ready")
    public static let userOkNeedPass = FTPResponse(code: 331, message: "Password required")
    public static let loginOk = FTPResponse(code: 230, message: "User logged in, proceed")
    public static let notLoggedIn = FTPResponse(code: 530, message: "Please login with USER and PASS")
    public static let loginFailed = FTPResponse(code: 530, message: "Login incorrect")
    public static let systemType = FTPResponse(code: 215, message: "UNIX Type: L8")
    public static let commandOk = FTPResponse(code: 200, message: "OK")
    public static let binaryMode = FTPResponse(code: 200, message: "Type set to I (Binary)")
    public static let fileOkBeginData = FTPResponse(code: 150, message: "Opening BINARY mode data connection")
    public static let transferComplete = FTPResponse(code: 226, message: "Transfer complete")
    public static let bye = FTPResponse(code: 221, message: "Goodbye")
    public static let fileUnavailable = FTPResponse(code: 550, message: "File or directory not found")
    public static let cannotOpenData = FTPResponse(code: 425, message: "Can't open data connection")
    public static let commandNotImplemented = FTPResponse(code: 502, message: "Command not implemented")
    public static let syntaxError = FTPResponse(code: 500, message: "Syntax error, command unrecognized")
    public static let lineTooLong = FTPResponse(code: 500, message: "Command line too long")
    public static let tooManyConnections = FTPResponse(code: 421, message: "Too many connections, please try again later")
    public static let idleTimeout = FTPResponse(code: 421, message: "Timeout: connection idle for too long")
    public static let securityNotSupported = FTPResponse(code: 504, message: "Security mechanism not supported (standard plain FTP only)")
    public static let resumeNotSupported = FTPResponse(code: 502, message: "Command not implemented (resume not supported for upload)")
    public static let transferAborted = FTPResponse(code: 426, message: "Connection closed; transfer aborted")
    
    public static func currentDirectory(_ path: String) -> FTPResponse {
        FTPResponse(code: 257, message: "\"\(path)\" is current directory")
    }
    
    /// Ответ на PASV: h1,h2,h3,h4,p1,p2
    public static func passiveMode(ip: String, port: UInt16) -> FTPResponse {
        let ipComponents = ip.split(separator: ".").compactMap { Int($0) }
        let h1 = ipComponents.count > 0 ? ipComponents[0] : 127
        let h2 = ipComponents.count > 1 ? ipComponents[1] : 0
        let h3 = ipComponents.count > 2 ? ipComponents[2] : 0
        let h4 = ipComponents.count > 3 ? ipComponents[3] : 1
        let p1 = Int(port / 256)
        let p2 = Int(port % 256)
        return FTPResponse(code: 227, message: "Entering Passive Mode (\(h1),\(h2),\(h3),\(h4),\(p1),\(p2))")
    }
    
    /// Ответ на EPSV: (|||port|)
    public static func extendedPassiveMode(port: UInt16) -> FTPResponse {
        FTPResponse(code: 229, message: "Entering Extended Passive Mode (|||\(port)|)")
    }
}
