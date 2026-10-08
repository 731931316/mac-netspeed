import Foundation

/// Holds explicit diagnostic options while leaving ordinary launches persistent.
struct LaunchOptions: Sendable {
    /// Enables the bounded startup and sampling smoke test.
    let smokeTest: Bool
    /// Receives the smoke report without collecting identifying machine details.
    let smokeReportURL: URL?
    /// Optionally receives the actual status image used during the smoke test.
    let renderPreviewURL: URL?

    /// Validates supported command-line options before starting AppKit.
    static func parse(arguments: [String]) throws -> LaunchOptions {
        var smokeTest = false
        var reportURL: URL?
        var previewURL: URL?
        var index = 0

        // Finder may supply an old process serial number argument on launch.
        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--smoke-test":
                smokeTest = true
            case "--smoke-report", "--smoke-preview", "--render-preview":
                guard index + 1 < arguments.count,
                      !arguments[index + 1].hasPrefix("--") else {
                    throw LaunchOptionError.missingPath(argument)
                }
                index += 1
                let destination = URL(fileURLWithPath: arguments[index])
                if argument == "--smoke-report" {
                    reportURL = destination
                } else {
                    previewURL = destination
                }
            default:
                guard argument.hasPrefix("-psn_") else {
                    throw LaunchOptionError.unsupportedArgument
                }
            }
            index += 1
        }

        guard !smokeTest || reportURL != nil else {
            throw LaunchOptionError.reportRequired
        }
        guard smokeTest || (reportURL == nil && previewURL == nil) else {
            throw LaunchOptionError.smokeTestRequired
        }
        return LaunchOptions(
            smokeTest: smokeTest,
            smokeReportURL: reportURL,
            renderPreviewURL: previewURL
        )
    }
}

/// Describes diagnostic usage errors without echoing user-supplied paths.
enum LaunchOptionError: Error, CustomStringConvertible {
    /// A supported file option has no following path.
    case missingPath(String)
    /// An unknown argument was passed to the application.
    case unsupportedArgument
    /// The bounded smoke test has no report destination.
    case reportRequired
    /// Diagnostic output was requested outside smoke-test mode.
    case smokeTestRequired

    /// Supplies an actionable, non-sensitive error for the command-line caller.
    var description: String {
        switch self {
        case .missingPath(let option):
            return "\(option) 需要一个输出文件路径。"
        case .unsupportedArgument:
            return "存在不支持的启动参数。"
        case .reportRequired:
            return "--smoke-test 需要同时指定 --smoke-report PATH。"
        case .smokeTestRequired:
            return "诊断输出需要同时启用 --smoke-test。"
        }
    }
}
