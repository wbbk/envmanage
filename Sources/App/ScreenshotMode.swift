import AppKit
import Foundation

/// 隐藏调试模式（供 README 截图等本地自动化使用）：
/// `EnvManage --screenshot <保存路径> [--page env|path|dup|runtime|project|settings]`
/// 窗口渲染完成后用 NSWindow 的 cacheDisplay 抓取主窗口自身内容
/// （进程内渲染，不需要屏幕录制权限），写完即退出。
enum ScreenshotMode {

    static var isActive: Bool { CommandLine.arguments.contains("--screenshot") }

    /// 截图保存路径（--screenshot 后一参数；缺省 /tmp）。
    static var targetPath: String {
        value(after: "--screenshot") ?? "/tmp/envmanage_screenshot.png"
    }

    /// 初始导航页（--page 后一参数）。
    static var pageName: String? { value(after: "--page") }

    private static func value(after flag: String) -> String? {
        guard let i = CommandLine.arguments.firstIndex(of: flag),
              i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }

    /// 延迟等待首帧渲染与数据回填后抓窗写 PNG，随后退出应用。
    static func capture(after seconds: Double = 3.0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            defer { NSApp.terminate(nil) }
            // 主窗口特征：内容宽度足够大（排除 MenuBarExtra 等小面板）
            guard let win = NSApp.windows.first(where: {
                $0.isVisible && $0.frame.width > 600
            }) ?? NSApp.windows.first(where: { $0.frame.width > 600 }) else { return }
            win.makeKeyAndOrderFront(nil)
            guard let view = win.contentView else { return }
            let rect = view.bounds
            guard let rep = view.bitmapImageRepForCachingDisplay(in: rect) else { return }
            view.cacheDisplay(in: rect, to: rep)
            guard let data = rep.representation(using: .png, properties: [:]) else { return }
            try? data.write(to: URL(fileURLWithPath: targetPath))
        }
    }
}
