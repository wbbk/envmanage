import Foundation

/// 检测到的一个语言运行时安装（跨 Python/Java/Node/Go/C++ 统一模型）。
struct RuntimeInstall: Identifiable, Equatable {
    let id = UUID()

    let language: RuntimeLanguage
    let version: String        // 例如 3.11.6 / 20.19.5 / 1.22.2 / 17.0.9
    let executable: String     // 主可执行文件绝对路径（已解析符号链接）
    let binDir: String         // 所在 bin 目录，用于激活时 PATH 前置
    let sourceLabel: String    // 来源展示："pyenv"、"Homebrew"、"系统自带"…
    var active: Bool           // 是否为当前默认生效版本
    let uninstallPaths: [String]       // 卸载=删除这些目录；空数组表示不可（安全）卸载
    let uninstallNeedsAdmin: Bool      // 删除是否需要管理员授权
    var environments: [RuntimeEnvironment] = []   // 挂在该版本下的虚拟环境

    /// 是否支持卸载（版本管理器/用户目录下的安装才允许直接删除）。
    var uninstallable: Bool { !uninstallPaths.isEmpty }

    static func == (lhs: RuntimeInstall, rhs: RuntimeInstall) -> Bool {
        lhs.executable == rhs.executable && lhs.language == rhs.language
    }
}
