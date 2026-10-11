import Foundation

/// Python 运行时提供者：检测 pyenv / conda / Homebrew / 官方安装包 / 系统 Python，
/// 并把 venv、virtualenv、conda env 等虚拟环境挂载到对应的基版本下展示。
struct PythonRuntimeProvider: LanguageRuntimeProvider {

    let language: RuntimeLanguage = .python

    func detect() -> [RuntimeInstall] {
        var installs: [RuntimeInstall] = []

        append(&installs, exe: "/usr/bin/python3", source: "系统自带",
               uninstall: [], needsAdmin: false)

        for base in ["/opt/homebrew/bin", "/usr/local/bin"] {
            for p in ShellTool.glob(base + "/python3.*") {
                append(&installs, exe: p, source: "Homebrew", uninstall: [], needsAdmin: false)
            }
        }
        for p in ShellTool.glob("/Library/Frameworks/Python.framework/Versions/*/bin/python3") {
            append(&installs, exe: p, source: "官方安装包", uninstall: [], needsAdmin: false)
        }
        for dir in ShellTool.glob(ShellFiles.expand("~/.pyenv/versions/*")) where ShellTool.isDir(dir) {
            let exe = dir + "/bin/python"
            guard FileManager.default.isExecutableFile(atPath: exe) else { continue }
            // pyenv-virtualenv 创建的“版本”其实是 venv，稍后作为虚拟环境挂载
            if FileManager.default.fileExists(atPath: dir + "/pyvenv.cfg") { continue }
            let name = (dir as NSString).lastPathComponent
            append(&installs, exe: exe, source: "pyenv " + name,
                   uninstall: [dir], needsAdmin: false)
        }
        for base in condaBases() {
            let exe = base + "/bin/python"
            guard FileManager.default.isExecutableFile(atPath: exe) else { continue }
            var install = makeInstall(exe: exe, source: "Conda " + (base as NSString).lastPathComponent,
                                      uninstall: [], needsAdmin: false)
            install?.environments = condaEnvironments(of: base)
            if let install { installs.append(install) }
        }

        // venv / virtualenv 挂载到基版本
        attachVirtualEnvs(&installs)

        var active = installs
        markActive(&active)
        return dedup(active)
    }

    // MARK: - 虚拟环境

    /// 扫描常见 venv 根目录（~/.virtualenvs、pyenv-virtualenv），按 pyvenv.cfg 的基路径/版本归属。
    private func attachVirtualEnvs(_ installs: inout [RuntimeInstall]) {
        var envs: [(path: String, base: String, version: String?)] = []

        // pyenv-virtualenv：~/.pyenv/versions/<name> 且含 pyvenv.cfg
        for dir in ShellTool.glob(ShellFiles.expand("~/.pyenv/versions/*")) where ShellTool.isDir(dir) {
            collectVenv(dir, into: &envs)
        }
        // 手工约定的虚拟环境根目录
        for root in ["~/.virtualenvs", "~/.venvs", "~/venvs"] {
            for dir in ShellTool.glob(ShellFiles.expand(root + "/*")) where ShellTool.isDir(dir) {
                collectVenv(dir, into: &envs)
            }
        }

        for env in envs {
            // 归属规则：pyvenv.cfg 的 version 前缀匹配，或 home 目录恰为基版本 binDir
            guard let idx = installs.firstIndex(where: { inst in
                if let v = env.version, !v.isEmpty, inst.version.hasPrefix(v) { return true }
                return env.base == inst.binDir
            }) else { continue }
            installs[idx].environments.append(
                RuntimeEnvironment(name: (env.path as NSString).lastPathComponent,
                                   path: env.path, kind: "venv", version: env.version))
        }
    }

    private func collectVenv(_ dir: String, into envs: inout [(path: String, base: String, version: String?)]) {
        let cfg = dir + "/pyvenv.cfg"
        guard let content = try? String(contentsOfFile: cfg, encoding: .utf8) else { return }
        var home = ""
        var version: String? = nil
        for line in content.components(separatedBy: .newlines) {
            let kv = line.split(separator: "=", maxSplits: 2)
            guard kv.count == 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespaces)
            let val = kv[1].trimmingCharacters(in: .whitespaces)
            if key == "home" { home = val }
            if key == "version" { version = val }
        }
        envs.append((dir, home, version))
    }

    /// conda 环境（不含 base）挂到对应 conda 安装下，版本从 lib/pythonX.Y 目录推断。
    /// 来源：base/envs/* 目录 + ~/.conda/environments.txt 登记（含 -p 创建的环境）。
    private func condaEnvironments(of base: String) -> [RuntimeEnvironment] {
        var dirs: [String] = ShellTool.glob(base + "/envs/*")
        let registry = ShellFiles.expand("~/.conda/environments.txt")
        if let list = try? String(contentsOfFile: registry, encoding: .utf8) {
            for line in list.components(separatedBy: .newlines) {
                let p = line.trimmingCharacters(in: .whitespaces)
                // 仅归属挂在该 base 下的环境
                if p.hasPrefix(base + "/") && p != base { dirs.append(p) }
            }
        }
        var result: [RuntimeEnvironment] = []
        var seen = Set<String>()
        for dir in dirs where ShellTool.isDir(dir) && seen.insert(dir).inserted {
            guard FileManager.default.isExecutableFile(atPath: dir + "/bin/python") else { continue }
            let name = (dir as NSString).lastPathComponent
            guard name != "bin" else { continue }   // 防止误收 base 内层目录
            var ver: String? = nil
            for lib in ShellTool.glob(dir + "/lib/python*") {
                let last = (lib as NSString).lastPathComponent
                if last.hasPrefix("python") {
                    ver = String(last.dropFirst(6))
                    break
                }
            }
            result.append(RuntimeEnvironment(name: name, path: dir, kind: "conda env", version: ver))
        }
        return result.sorted { $0.name < $1.name }
    }

    private func condaBases() -> [String] {
        var bases = Set<String>()
        if let conda = ShellTool.which("conda") {
            // .../base/bin/conda → .../base
            bases.insert((conda as NSString).deletingLastPathComponent
                .replacingOccurrences(of: "/bin", with: ""))
        }
        for cand in ["~/miniconda3", "~/anaconda3", "~/opt/anaconda3", "~/opt/miniconda3",
                     "/opt/anaconda3", "/opt/miniconda3"] {
            let p = ShellFiles.expand(cand)
            if FileManager.default.isExecutableFile(atPath: p + "/bin/python") { bases.insert(p) }
        }
        return Array(bases)
    }

    // MARK: - 工具

    private func append(_ installs: inout [RuntimeInstall], exe: String, source: String,
                        uninstall: [String], needsAdmin: Bool) {
        if let install = makeInstall(exe: exe, source: source,
                                     uninstall: uninstall, needsAdmin: needsAdmin) {
            installs.append(install)
        }
    }

    private func makeInstall(exe: String, source: String,
                             uninstall: [String], needsAdmin: Bool) -> RuntimeInstall? {
        guard FileManager.default.isExecutableFile(atPath: exe) else { return nil }
        guard let ver = pythonVersion(of: exe) else { return nil }
        let real = (exe as NSString).resolvingSymlinksInPath
        return RuntimeInstall(language: .python, version: ver, executable: real,
                              binDir: (real as NSString).deletingLastPathComponent,
                              sourceLabel: source, active: false,
                              uninstallPaths: uninstall, uninstallNeedsAdmin: needsAdmin)
    }

    private func pythonVersion(of exe: String) -> String? {
        guard let out = ShellTool.runCapture(exe, ["-V"]) else { return nil }
        for token in out.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" })
        where token.contains(".") && token.first?.isNumber == true {
            return String(token)
        }
        return nil
    }

    private func dedup(_ installs: [RuntimeInstall]) -> [RuntimeInstall] {
        var seen = Set<String>()
        return installs.filter {
            seen.insert($0.executable).inserted
        }.sorted { versionCompare($0.version, $1.version) }
    }
}
