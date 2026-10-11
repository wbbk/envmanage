import Foundation

/// 全局常量与关键路径。
enum AppInfo {
    static let appName = "EnvManage"
    static let version = "1.0.0"
    static let bundleId = "com.envmanage.app"

    /// 在源文件中用来标记「被禁用」的可还原注释前缀。
    static let disableMarker = "#ENVManage-disabled#"

    /// 运行时激活受管块标记（按语言写入 ~/.zshrc）。
    static func runtimeMarkBegin(_ lang: RuntimeLanguage) -> String {
        "# >>> EnvManage Runtime:\(lang.rawValue) >>>"
    }
    static func runtimeMarkEnd(_ lang: RuntimeLanguage) -> String {
        "# <<< EnvManage Runtime:\(lang.rawValue) <<<"
    }

    /// 旧版 Python 受管块标记（仅用于升级时清理）。
    static let pyMarkBegin = "# >>> EnvManage Python 默认版本 >>>"
    static let pyMarkEnd = "# <<< EnvManage Python 默认版本 <<<"

    /// 备份目录：~/Library/Application Support/EnvManage/Backups
    static var backupDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("EnvManage/Backups")
    }
}

/// Shell 配置文件位置（按加载顺序，越靠后优先级越高）。
enum ShellFiles {
    static let systemFiles = [
        "/etc/zshenv", "/etc/zprofile", "/etc/zshrc",
        "/etc/profile", "/etc/bashrc", "/etc/bashrc_Apple_Terminal",
    ]

    static var userFiles: [String] {
        let home = NSHomeDirectory()
        return [
            home + "/.zshenv", home + "/.zprofile", home + "/.zshrc",
            home + "/.bash_profile", home + "/.bash_login", home + "/.profile", home + "/.bashrc",
            // Fish 配置只读识别（F10-07）
            home + "/.config/fish/config.fish",
        ]
    }

    /// 默认新增用户变量写入位置。
    static var defaultUserFile: String { NSHomeDirectory() + "/.zshrc" }
    /// 默认新增系统变量写入位置。
    static let defaultSystemFile = "/etc/zshenv"

    /// 解析 ~ 前缀。
    static func expand(_ p: String) -> String {
        (p as NSString).expandingTildeInPath
    }
}
