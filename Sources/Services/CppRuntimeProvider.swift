import Foundation

/// C/C++ 编译器提供者：检测 Apple Clang（系统）、Homebrew GCC（g++-NN）与 LLVM。
struct CppRuntimeProvider: LanguageRuntimeProvider {

    let language: RuntimeLanguage = .cpp

    func detect() -> [RuntimeInstall] {
        var installs: [RuntimeInstall] = []

        // Apple Clang（随 Xcode CLT，不可卸载）
        append(&installs, exe: "/usr/bin/clang++", source: "Apple Clang（系统）")
        // Homebrew 版本化 GCC：/opt/homebrew/bin/g++-13 等
        for base in ["/opt/homebrew/bin", "/usr/local/bin"] {
            for p in ShellTool.glob(base + "/g++-*") {
                append(&installs, exe: p, source: "Homebrew GCC")
            }
        }
        // Homebrew LLVM
        for dir in ["/opt/homebrew/opt/llvm", "/usr/local/opt/llvm"] {
            append(&installs, exe: dir + "/bin/clang++", source: "Homebrew LLVM")
        }

        markActive(&installs)
        return installs.sorted { versionCompare($0.version, $1.version) }
    }

    // MARK: - 工具

    private func append(_ installs: inout [RuntimeInstall], exe: String, source: String) {
        guard FileManager.default.isExecutableFile(atPath: exe) else { return }
        guard let ver = compilerVersion(of: exe) else { return }
        let real = (exe as NSString).resolvingSymlinksInPath
        installs.append(RuntimeInstall(language: .cpp, version: ver, executable: real,
                                       binDir: (real as NSString).deletingLastPathComponent,
                                       sourceLabel: source, active: false,
                                       uninstallPaths: [], uninstallNeedsAdmin: false))
    }

    /// clang++ --version: "Apple clang version 15.0.0 (clang-1500.3.9.4)" / "clang version 16.0.0"
    /// g++-13 --version:  "g++ (Homebrew GCC 13.2.0) 13.2.0"
    private func compilerVersion(of exe: String) -> String? {
        guard let out = ShellTool.runCapture(exe, ["--version"]) else { return nil }
        guard let first = out.components(separatedBy: .newlines).first else { return nil }
        for token in first.split(separator: " ") {
            let s = String(token.trimmingCharacters(in: CharacterSet(charactersIn: "(,)")))
            if s.count >= 3, s.first?.isNumber == true, s.contains(".") {
                return s
            }
        }
        return nil
    }
}
