import Foundation

/// Java 运行时提供者：检测系统 JDK（/Library/Java/JavaVirtualMachines）、
/// SDKMAN!（~/.sdkman/candidates/java）与 Homebrew OpenJDK。
/// 激活时写入 JAVA_HOME + PATH 前置块。
struct JavaRuntimeProvider: LanguageRuntimeProvider {

    let language: RuntimeLanguage = .java

    func detect() -> [RuntimeInstall] {
        var installs: [RuntimeInstall] = []

        // 系统安装目录 JDK（pkg 安装，删除通常需要管理员）
        for home in ShellTool.glob("/Library/Java/JavaVirtualMachines/*/Contents/Home") {
            append(&installs, home: home, source: "系统 JDK",
                   uninstall: [((home as NSString).deletingLastPathComponent as NSString)
                       .deletingLastPathComponent],           // JDK 目录本身
                   needsAdmin: !FileManager.default.isWritableFile(atPath: "/Library/Java/JavaVirtualMachines"))
        }
        // SDKMAN!（用户目录，可直接删除）
        for dir in ShellTool.glob(ShellFiles.expand("~/.sdkman/candidates/java/*"))
        where ShellTool.isDir(dir) && !dir.hasSuffix("/current") {
            append(&installs, home: dir, source: "SDKMAN!",
                   uninstall: [dir], needsAdmin: false)
        }
        // Homebrew（交给 brew uninstall，不代删）
        for base in ["/opt/homebrew/opt", "/usr/local/opt"] {
            for dir in ShellTool.glob(base + "/openjdk@*") where ShellTool.isDir(dir) {
                append(&installs, home: dir, source: "Homebrew", uninstall: [], needsAdmin: false)
            }
        }

        markActive(&installs)
        return installs.sorted { versionCompare($0.version, $1.version) }
    }

    /// Java 激活需要同时设置 JAVA_HOME。
    func activationBlock(for install: RuntimeInstall) -> String {
        var home = install.binDir
        if home.hasSuffix("/bin") { home = String(home.dropLast(4)) }
        return "export JAVA_HOME=\"\(home)\"\nexport PATH=\"$JAVA_HOME/bin:$PATH\""
    }

    /// Java 的默认判定走 /usr/libexec/java_home，而非 which java（/usr/bin/java 是转发 stub）。
    func markActive(_ installs: inout [RuntimeInstall]) {
        var defHome: String? = nil
        if let out = ShellTool.runCapture("/usr/libexec/java_home", []) {
            defHome = out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let defBin = defHome.map { $0 + "/bin" }
        for i in installs.indices {
            if let defBin, installs[i].binDir == defBin { installs[i].active = true }
        }
        if installs.allSatisfy({ !$0.active }), let hit = ShellTool.which("java") {
            let real = (hit as NSString).resolvingSymlinksInPath
            for i in installs.indices where installs[i].executable == real {
                installs[i].active = true
            }
        }
    }

    // MARK: - 工具

    private func append(_ installs: inout [RuntimeInstall], home: String, source: String,
                        uninstall: [String], needsAdmin: Bool) {
        let exe = home + "/bin/java"
        guard FileManager.default.isExecutableFile(atPath: exe) else { return }
        guard let ver = javaVersion(of: exe) else { return }
        let real = (exe as NSString).resolvingSymlinksInPath
        installs.append(RuntimeInstall(language: .java, version: ver, executable: real,
                                       binDir: (real as NSString).deletingLastPathComponent,
                                       sourceLabel: source, active: false,
                                       uninstallPaths: uninstall, uninstallNeedsAdmin: needsAdmin))
    }

    /// `java -version` 输出在 stderr：openjdk version "17.0.9" 2023-10-17
    private func javaVersion(of exe: String) -> String? {
        guard let out = ShellTool.runCapture(exe, ["-version"]) else { return nil }
        for line in out.components(separatedBy: .newlines) {
            if let start = line.range(of: "\""),
               let end = line.range(of: "\"", options: [], range: start.upperBound..<line.endIndex) {
                let quoted = String(line[start.upperBound..<end.lowerBound])
                if quoted.contains(".") {
                    return quoted.hasPrefix("1.") ? String(quoted.dropFirst(2)) : quoted
                }
            }
        }
        return nil
    }
}
