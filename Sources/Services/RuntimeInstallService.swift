import Foundation

/// 一种可用的安装渠道（版本管理器 / 包管理器）。
struct InstallManager: Identifiable {
    let id = UUID()
    let label: String          // "pyenv" / "Homebrew" / "nvm" …
    let available: Bool        // 本机是否已具备该管理器
    let hint: String           // 版本示例 / 不可用时的提示
    let command: (String) -> String   // 输入版本号生成 shell 命令串
    let listCommand: String?   // 拉取可安装版本列表的命令（nil = 不支持列举）
}

/// 通过本机已有的版本管理器安装指定语言版本（安装过程输出流式回传界面）。
enum RuntimeInstallService {

    /// 各语言可用的安装渠道（官方渠道排第 1 位，作为默认选择）。
    static func managers(for lang: RuntimeLanguage) -> [InstallManager] {
        let home = ShellFiles.expand("~")
        switch lang {
        case .python:
            return [
                InstallManager(label: "Python 官方（python.org）", available: officialAvailable,
                               hint: "官方 .pkg，需管理员密码；请选完整版本号",
                               command: { v in officialPkg(name: "Python", version: v, urls: [
                                   "https://www.python.org/ftp/python/\(v)/python-\(v)-macos11.pkg",
                                   "https://www.python.org/ftp/python/\(v)/python-\(v).pkg",
                               ]) },
                               listCommand: "curl -fsSL https://www.python.org/ftp/python/"),
                InstallManager(label: "pyenv", available: ShellTool.which("pyenv") != nil,
                               hint: "如 3.12.1（源码编译安装）",
                               command: { "pyenv install -s \($0)" },
                               listCommand: "pyenv install --list"),
                InstallManager(label: "Homebrew", available: brew != nil,
                               hint: "如 3.12（formula：python@3.12）",
                               command: { "brew install python@\(normalized($0))" },
                               listCommand: "brew search /^python@/"),
            ]
        case .java:
            return [
                InstallManager(label: "Eclipse Temurin 官方（Adoptium）", available: officialAvailable,
                               hint: "官方 .pkg，按特性版本安装最新 GA，需管理员密码",
                               command: { v in officialPkg(name: "JDK", version: v, urls: [
                                   "https://api.adoptium.net/v3/binary/latest/\(majorOf(v))/ga/mac/\(archJava)/jdk/hotspot/normal/eclipse",
                               ]) },
                               listCommand: "curl -fsSL https://api.adoptium.net/v3/info/release_names"),
                InstallManager(label: "SDKMAN!", available: FileManager.default.fileExists(atPath: home + "/.sdkman/bin/sdkman-init.sh"),
                               hint: "如 21.0.2-tem（sdk list java 可查）",
                               command: { "source \(ShellTool.shq(home + "/.sdkman/bin/sdkman-init.sh")) && sdk install java \($0)" },
                               listCommand: "source \(ShellTool.shq(home + "/.sdkman/bin/sdkman-init.sh")) && sdk list java"),
                InstallManager(label: "Homebrew", available: brew != nil,
                               hint: "如 17（formula：openjdk@17）",
                               command: { "brew install openjdk@\(normalized($0))" },
                               listCommand: "brew search /^openjdk@/"),
            ]
        case .nodejs:
            return [
                InstallManager(label: "Node.js 官方（nodejs.org）", available: officialAvailable,
                               hint: "官方 .pkg，需管理员密码；请选完整版本号",
                               command: { v in officialPkg(name: "Node.js", version: v, urls: [
                                   "https://nodejs.org/dist/v\(v)/node-v\(v).pkg",
                               ]) },
                               listCommand: "curl -fsSL https://nodejs.org/dist/index.json | grep -oE '\"version\":\"v[0-9.]+\"'"),
                InstallManager(label: "nvm", available: FileManager.default.fileExists(atPath: home + "/.nvm/nvm.sh"),
                               hint: "如 20 / 20.19.5（nvm ls-remote 可查）",
                               command: { "source \(ShellTool.shq(home + "/.nvm/nvm.sh")) && nvm install \($0)" },
                               listCommand: "source \(ShellTool.shq(home + "/.nvm/nvm.sh")) && nvm ls-remote"),
                InstallManager(label: "fnm", available: ShellTool.which("fnm") != nil,
                               hint: "如 20.19.5",
                               command: { "fnm install \($0)" },
                               listCommand: "fnm ls-remote"),
                InstallManager(label: "Volta", available: ShellTool.which("volta") != nil,
                               hint: "如 20.19.5",
                               command: { "volta install node@\($0)" },
                               listCommand: nil),
                InstallManager(label: "Homebrew", available: brew != nil,
                               hint: "如 22（formula：node@22）",
                               command: { "brew install node@\(normalized($0))" },
                               listCommand: "brew search /^node@/"),
            ]
        case .go:
            return [
                InstallManager(label: "Go 官方（go.dev）", available: officialAvailable,
                               hint: "官方 .pkg，需管理员密码；请选完整版本号",
                               command: { v in officialPkg(name: "Go", version: v, urls: [
                                   "https://go.dev/dl/go\(v).darwin-\(archGo).pkg",
                               ]) },
                               listCommand: "curl -fsSL 'https://go.dev/dl/?mode=json&include=all'"),
                InstallManager(label: "Homebrew", available: brew != nil,
                               hint: "如 1.22（formula：go@1.22）",
                               command: { "brew install go@\(normalized($0))" },
                               listCommand: "brew search /^go@/"),
            ]
        case .cpp:
            return [
                InstallManager(label: "Apple 官方工具链（Xcode CLT）", available: FileManager.default.isExecutableFile(atPath: "/usr/bin/xcode-select"),
                               hint: "xcode-select --install，提供 clang/clang++",
                               command: { _ in "xcode-select --install" },
                               listCommand: nil),
                InstallManager(label: "Homebrew GCC", available: brew != nil,
                               hint: "如 13（formula：gcc@13）",
                               command: { "brew install gcc@\(normalized($0))" },
                               listCommand: "brew search /^gcc@/"),
                InstallManager(label: "Homebrew LLVM", available: brew != nil,
                               hint: "clang/clang++，直接安装 llvm",
                               command: { _ in "brew install llvm" },
                               listCommand: nil),
            ]
        }
    }

    /// 启动安装：异步执行命令，逐行回传输出（主线程），结束时回传退出码。
    static func install(manager: InstallManager, version: String,
                        onLine: @escaping (String) -> Void,
                        onDone: @escaping (Int32) -> Void) {
        let v = sanitized(version)
        guard !v.isEmpty else {
            DispatchQueue.main.async {
                onLine("版本号不合法（仅允许字母、数字、点、下划线、连字符、@）。")
                onDone(-1)
            }
            return
        }
        let cmd = manager.command(v)
        onLine("$ \(cmd)")
        ShellTool.runShellAsync(cmd, onLine: onLine, onDone: onDone)
    }

    /// 异步拉取该渠道可安装的版本号列表（主线程回调；失败/不支持回空数组）。
    static func fetchVersions(manager: InstallManager, onResult: @escaping ([String]) -> Void) {
        guard manager.available, let cmd = manager.listCommand else {
            DispatchQueue.main.async { onResult([]) }
            return
        }
        var buffer = ""
        ShellTool.runShellAsync(cmd,
                                onLine: { line in buffer += line + "\n" },
                                onDone: { code in
            _ = code
            onResult(parseVersions(buffer))
        })
    }

    /// 从命令输出中提取版本号候选（形如 3.12.1 / 22.14.0 / 21.0.2-tem / python@3.11）。
    static func parseVersions(_ output: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: "\\d+\\.\\d+(?:\\.\\d+)*(?:[-.]?(?:rc|b|alpha|beta|dev|tem|jre|jdk|a)[-\\d]*)?",
            options: []) else { return [] }
        let ns = output as NSString
        var seen = Set<String>()
        var result: [String] = []
        for m in regex.matches(in: output, options: [],
                               range: NSRange(location: 0, length: ns.length)) {
            let v = ns.substring(with: m.range).trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
            guard v.contains("."), v.count <= 20, seen.insert(v).inserted else { continue }
            result.append(v)
        }
        // 先排序再截断：列表页常为升序，提前 break 会丢掉最新版本
        let sorted = result.sorted { a, b in
            let pa = a.split(separator: ".").map { Int($0) ?? 0 }
            let pb = b.split(separator: ".").map { Int($0) ?? 0 }
            for i in 0..<max(pa.count, pb.count) {
                let x = i < pa.count ? pa[i] : 0
                let y = i < pb.count ? pb[i] : 0
                if x != y { return x > y }
            }
            return false
        }
        return Array(sorted.prefix(250))
    }

    // MARK: - 官方渠道工具

    /// 官方渠道依赖 /usr/bin/curl（macOS 自带）。
    private static var officialAvailable: Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/curl")
    }

    /// 架构探测（Adoptium 用 aarch64/x64，Go 用 arm64/amd64）。
    private static let archJava = #"$( [ "$(uname -m)" = "arm64" ] && echo aarch64 || echo x64 )"#
    private static let archGo = #"$( [ "$(uname -m)" = "arm64" ] && echo arm64 || echo amd64 )"#

    /// 取版本号的 major（Temurin 按特性版本取最新 GA）。
    private static func majorOf(_ v: String) -> String {
        String(v.split(separator: ".").first ?? "8")
    }

    /// 生成「下载官方 pkg + 管理员授权 installer 安装」的 shell 命令串。
    /// 版本号已经过 sanitized 清洗，tmp 路径固定，无注入风险。
    private static func officialPkg(name: String, version: String, urls: [String]) -> String {
        let tmp = "/tmp/EnvManage-\(name.replacingOccurrences(of: ".", with: ""))-\(version).pkg"
        let tries = urls.map { "curl -fL --progress-bar -o \(ShellTool.shq(tmp)) \"\($0)\"" }
            .joined(separator: " || ")
        return """
        echo "📥 下载 \(name) \(version) 官方安装包…"; \
        \(tries) && \
        echo "🔐 安装到系统（需要管理员密码）…" && \
        /usr/bin/osascript -e 'do shell script "installer -pkg \(tmp) -target /" with administrator privileges' && \
        rm -f \(ShellTool.shq(tmp)) && echo "✅ \(name) \(version) 安装完成" || \
        echo "❌ 安装失败或已取消，请查看上方日志"
        """
    }

    // MARK: - 工具

    private static var brew: String? {
        ShellTool.which("brew") ??
            (FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew") ? "/opt/homebrew/bin/brew" : nil) ??
            (FileManager.default.isExecutableFile(atPath: "/usr/local/bin/brew") ? "/usr/local/bin/brew" : nil)
    }

    /// brew formula 后缀常只取 major.minor。
    private static func normalized(_ v: String) -> String {
        let parts = v.split(separator: ".")
        return parts.count >= 2 ? "\(parts[0]).\(parts[1])" : v
    }

    /// 防注入：仅保留安全字符。
    private static func sanitized(_ v: String) -> String {
        let allowed = CharacterSet(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._@-")
        return v.trimmingCharacters(in: .whitespacesAndNewlines)
            .unicodeScalars.filter { allowed.contains($0) }
            .map { String($0) }.joined()
    }
}
