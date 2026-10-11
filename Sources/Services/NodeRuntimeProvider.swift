import Foundation

/// Node.js 运行时提供者：检测 nvm / fnm / volta / Homebrew / 官方安装。
struct NodeRuntimeProvider: LanguageRuntimeProvider {

    let language: RuntimeLanguage = .nodejs

    func detect() -> [RuntimeInstall] {
        var installs: [RuntimeInstall] = []
        let home = ShellFiles.expand("~")

        // nvm：~/.nvm/versions/node/vX.Y.Z/bin/node（可直接删除版本目录）
        for dir in ShellTool.glob(home + "/.nvm/versions/node/*") where ShellTool.isDir(dir) {
            append(&installs, exe: dir + "/bin/node", source: "nvm",
                   uninstall: [dir], needsAdmin: false)
        }
        // fnm：~/.fnm 或 ~/.local/share/fnm 下的 node-versions
        for root in [home + "/.fnm", home + "/.local/share/fnm"] {
            for dir in ShellTool.glob(root + "/node-versions/*/installation") where ShellTool.isDir(dir) {
                append(&installs, exe: dir + "/bin/node", source: "fnm",
                       uninstall: [(dir as NSString).deletingLastPathComponent], needsAdmin: false)
            }
        }
        // volta：~/.volta/tools/image/node/X.Y.Z
        for dir in ShellTool.glob(home + "/.volta/tools/image/node/*") where ShellTool.isDir(dir) {
            append(&installs, exe: dir + "/bin/node", source: "Volta",
                   uninstall: [dir], needsAdmin: false)
        }
        // Homebrew 版本化 formula：opt/node@22 等
        for base in ["/opt/homebrew/opt", "/usr/local/opt"] {
            for dir in ShellTool.glob(base + "/node@*") where ShellTool.isDir(dir) {
                append(&installs, exe: dir + "/bin/node", source: "Homebrew",
                       uninstall: [], needsAdmin: false)
            }
        }
        // 通用 bin（官方 pkg 或 brew 链接）
        for exe in ["/opt/homebrew/bin/node", "/usr/local/bin/node"] {
            append(&installs, exe: exe, source: "系统 / 官方安装",
                   uninstall: [], needsAdmin: false)
        }

        markActive(&installs)
        return dedup(installs)
    }

    // MARK: - 工具

    private func append(_ installs: inout [RuntimeInstall], exe: String, source: String,
                        uninstall: [String], needsAdmin: Bool) {
        guard FileManager.default.isExecutableFile(atPath: exe) else { return }
        guard let out = ShellTool.runCapture(exe, ["-v"]),
              out.hasPrefix("v") else { return }
        let ver = String(out.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        let real = (exe as NSString).resolvingSymlinksInPath
        installs.append(RuntimeInstall(language: .nodejs, version: ver, executable: real,
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
