import Foundation

/// 一行 GUI（当前进程/launchd）与 Shell（zsh -lc）环境的差异。
struct EnvDiffRow: Identifiable, Hashable {
    enum Kind: String {
        case onlyInShell = "仅 Shell 有"
        case onlyInGUI   = "仅 GUI 有"
        case valueDiff   = "值不同"
    }
    var id: String { name }
    let name: String
    let kind: Kind
    let shellValue: String?
    let guiValue: String?
}

/// 环境差异诊断服务（F10-02）：对比登录 Shell 的实际环境与
/// 当前 GUI 进程环境，帮助解释"终端里有效、双击打开的 App 里无效"。
enum DiagnosticsService {

    /// 对比噪音变量：每次启动 Shell 都会生成的临时/终端变量。
    static let noiseNames: Set<String> = [
        "TERM", "TERMINAL_EMULATOR", "SHLVL", "PWD", "OLDPWD", "_",
        "XPC_SERVICE_NAME", "XPC_FLAGS", "SECURITYSESSIONID", "TMPDIR",
        "COMMAND_MODE", "LOGIN_SHELL", "ZSH", "P9K_SSH", "P9K_TTY",
        "PS1", "PS2", "RPS1", "RPROMPT", "LSCOLORS", "GREP_COLOR",
    ]

    /// 采集登录 Shell（zsh -lc）的完整环境。超时或失败返回 nil。
    static func captureShellEnv(timeout: TimeInterval = 12) -> [String: String]? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", "env -0"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch {
            return nil
        }
        // 简单超时保护：10 秒内等待退出，否则终止
        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if proc.isRunning {
            proc.terminate()
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        var dict: [String: String] = [:]
        for item in text.split(separator: "\0", omittingEmptySubsequences: true) {
            let s = String(item)
            if let eq = s.firstIndex(of: "=") {
                dict[String(s[..<eq])] = String(s[s.index(after: eq)...])
            }
        }
        return dict
    }

    /// 对比：登录 Shell 环境 vs 当前 GUI 进程环境（排除噪音变量与差异巨大的项）。
    static func compare() -> [EnvDiffRow] {
        guard let shell = captureShellEnv() else { return [] }
        let gui = ProcessInfo.processInfo.environment
        var rows: [EnvDiffRow] = []
        let names = Set(shell.keys).union(gui.keys).subtracting(noiseNames)
        for name in names.sorted() {
            let sv = shell[name], gv = gui[name]
            if let sv, let gv {
                if sv != gv {
                    // 忽略仅末尾差异（如 PATH 尾冒号）之外的展示噪音，值原样返回
                    rows.append(EnvDiffRow(name: name, kind: .valueDiff, shellValue: sv, guiValue: gv))
                }
            } else if let sv {
                _ = sv
                rows.append(EnvDiffRow(name: name, kind: .onlyInShell, shellValue: sv, guiValue: nil))
            } else if let gv {
                _ = gv
                rows.append(EnvDiffRow(name: name, kind: .onlyInGUI, shellValue: nil, guiValue: gv))
            }
        }
        return rows
    }
}
