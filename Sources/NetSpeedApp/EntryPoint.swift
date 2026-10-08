import AppKit
import Darwin
import OSLog

/// Starts the native menu-bar application or its explicitly requested smoke test.
@main
struct NetSpeedEntryPoint {
    /// Runs AppKit on the main actor and keeps the delegate alive for the run loop.
    @MainActor
    static func main() {
        let logger = Logger(subsystem: "io.github.mac-netspeed", category: "Application")
        do {
            let options = try LaunchOptions.parse(arguments: Array(CommandLine.arguments.dropFirst()))
            let application = NSApplication.shared
            // LSUIElement already selects accessory mode in a bundle; AppKit returns
            // false when setting an unchanged policy, which is a successful state.
            guard application.activationPolicy() == .accessory
                    || application.setActivationPolicy(.accessory) else {
                logger.error("无法设置菜单栏应用运行模式")
                exit(1)
            }
            let delegate = NetSpeedApplicationDelegate(options: options)
            application.delegate = delegate
            withExtendedLifetime(delegate) {
                application.run()
            }
        } catch {
            logger.error("启动参数校验失败")
            let message = "\(error)\n"
            FileHandle.standardError.write(Data(message.utf8))
            exit(64)
        }
    }
}
