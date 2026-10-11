import Foundation

/// Go 运行时提供者：检测官方 pkg（/usr/local/go）、gimme/手工安装（~/sdk、~/tools）、Homebrew。
struct GoRuntimeProvider: LanguageRuntimeProvider {

    let language: RuntimeLanguage = .go

    func detect() -> [RuntimeInstall] {
        var installs: [RuntimeInstall] = []
        let home = ShellFiles.expand("~")

        // 官方安装包：/usr/local/go（删除一般需要管理员）
        append(&installs, root: "/usr/local/go", source: "官方安装包",
               needsAdmin: !FileManager.default.isWritableFile(atPath: "/usr/local"))
        // gimme / 手工多版本：~/sdk/goX.Y.Z、~/tools/goX.Y.Z
        for pattern in [home + "/sdk/go*", home + "/tools/go*"] {
            for dir in ShellTool.glob(pattern) where ShellTool.isDir(dir) {
                append(&installs, root: dir, source: "gimme / 手动安装", needsAdmin: false)
            }
        }
        // Homebrew
        for base in ["/opt/homebrew/opt", "/usr/local/opt"] {
            for dir in ShellTool.glob(base + "/go@*") where ShellTool.isDir(dir) {
                appendBin(&installs, exe: dir + "/bin/go", source: "Homebrew")
            }
        }
        appendBin(&installs, exe: "/opt/homebrew/bin/go", source: "Homebrew")
        appendBin(&installs, exe: "/usr/local/bin/go", source: "Homebrew")

        markActive(&installs)
        return dedup(installs)
    }

    // MARK: - 工具

    private func append(_ installs: inout [RuntimeInstall], root: String,
                        source: String, needsAdmin: Bool) {
        appendBin(&installs, exe: root + "/bin/go", source: source,
                  uninstall: [root], needsAdmin: needsAdmin)
    }

    private func appendBin(_ installs: inout [RuntimeInstall], exe: String, source: String,
                           uninstall: [String] = [], needsAdmin: Bool = false) {
        guard FileManager.default.isExecutableFile(atPath: exe) else { return }
        // "go version go1.22.2 darwin/arm64"
        guard let out = ShellTool.runCapture(exe, ["version"]) else { return }
        guard let token = out.split(separator: " ").first(where: { $0.hasPrefix("go") && $0.count > 2 }),
              token.contains(".") else { return }
        let ver = String(token.dropFirst(2))
        let real = (exe as NSString).resolvingSymlinksInPath
        installs.append(RuntimeInstall(language: .go, version: ver, executable: real,
                                       binDir: (real as NSString).deletingLastPathComponent,
                                       sourceLabel: source, active: false,
                                       uninstallPaths: uninstall, uninstallNeedsAdmin: needsAdmin))
    }

    private func dedup(_ installs: [RuntimeInstall]) -> [RuntimeInstall] {
        var seen = Set<String>()
        return installs.filter { seen.insert($0.executable).inserted }
            .sorted { versionCompare($0.version, $1.version) }
    }
}
