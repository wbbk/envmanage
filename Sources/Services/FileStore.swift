import Foundation
import CryptoKit

/// 统一文件写入层：封装「读取 / 外部修改校验 / 语法预检 / 备份 / 撤销记录 / 落盘 / 审计」。
/// 供 EditService 与 RuntimeService 共用，保证所有写操作行为一致、可撤销、可追溯。
final class FileStore {

    let backup = BackupService()
    var undo: FileSnapshotUndoManager?

    /// 扫描时登记的基线哈希（path → 内容 sha256；"missing" 表示扫描时不存在）。
    private var scanHashes: [String: String] = [:]
    /// 当前事务标签（审计日志用）。
    private var currentLabel: String = "write"

    /// 字符串内容的 sha256 十六进制。
    static func sha256(_ s: String) -> String {
        SHA256.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 读取

    /// 读取文本内容（不存在返回空串）。
    func read(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    func readLines(_ path: String) -> [String] {
        read(path).components(separatedBy: .newlines)
    }

    // MARK: - 扫描基线（F08 外部修改校验）

    /// 扫描完成后登记基线哈希，写入前据此拒绝覆盖 GUI 不知情的外部修改。
    func markScanned(paths: [String]) {
        for p in paths where FileManager.default.fileExists(atPath: p) {
            scanHashes[p] = Self.sha256(read(p))
        }
        for p in paths where !FileManager.default.fileExists(atPath: p) {
            scanHashes[p] = "missing"
        }
    }

    // MARK: - 写入流水线

    /// 把 content 写入 path：基线校验 → 语法预检 → 备份 → 撤销快照 → 落盘 → 审计。
    func write(content: String, to path: String) throws {
        let before = read(path)

        // 1. 外部修改校验
        if let baseline = scanHashes[path] {
            if baseline == "missing" && !before.isEmpty {
                throw EditError("文件在扫描后新建或被外部改动：\(path)。请点「刷新」后重试。")
            } else if baseline != "missing" && Self.sha256(before) != baseline {
                throw EditError("文件自上次扫描后已被外部修改：\(path)。请点「刷新」后重试。")
            }
        }

        // 2. 语法预检（zsh -n / fish -n），防止写坏 shell 配置
        try Self.syntaxPrecheck(content: content, asShellFileAt: path)

        // 3. 备份 + 撤销快照 + 落盘 + 审计
        let privileged = !FileManager.default.isWritableFile(atPath: path)
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: path).deletingLastPathComponent(),
            withIntermediateDirectories: true)
        backup.backup(path)
        undo?.record(path: path, before: before, after: content)
        do {
            try applyWrite(content: content, to: path)
        } catch {
            WriteAudit.log(action: currentLabel, file: path, privileged: privileged,
                           result: "失败：\(error.localizedDescription)")
            throw error
        }
        WriteAudit.log(action: currentLabel, file: path, privileged: privileged, result: "成功")

        // 4. 更新基线，允许同一事务内对同文件连续写
        scanHashes[path] = Self.sha256(content)
    }

    /// 仅落盘：普通权限不足时回退到管理员授权。不做备份/撤销/预检（供撤销恢复使用）。
    func applyWrite(content: String, to path: String) throws {
        if FileManager.default.isWritableFile(atPath: path) {
            do {
                try content.write(toFile: path, atomically: true, encoding: .utf8)
                return
            } catch {
                throw EditError("写入失败：\(error.localizedDescription)")
            }
        }
        try adminWrite(content: content, to: path)
    }

    /// 开启一个可撤销事务并执行 body；嵌套调用会复用外层事务。
    func transaction<T>(_ label: String, _ body: () throws -> T) throws -> T {
        let owned = undo?.begin(label) ?? false
        let outer = currentLabel
        currentLabel = label
        defer { currentLabel = outer; if owned { undo?.commit() } }
        return try body()
    }

    // MARK: - 语法预检（F08）

    /// 将内容写入临时文件并用对应解释器做 -n 语法检查；失败抛 EditError。
    /// 检查器无法启动时不阻塞主流程（环境问题不应阻止保存）。
    static func syntaxPrecheck(content: String, asShellFileAt path: String) throws {
        let lower = path.lowercased()
        let isFish = lower.hasSuffix(".fish") || lower.contains("/fish/")
        let isShellish = ["zsh", "bash", "profile", "shrc", "shenv", "zlogin", "login"].contains {
            lower.contains($0)
        }
        guard isFish || isShellish else { return }

        let exe: String
        var interpreterArgs: [String]
        if isFish {
            let candidates = ["/usr/local/bin/fish", "/opt/homebrew/bin/fish"]
            guard let f = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            else { return }
            exe = f
            interpreterArgs = ["--no-execute"]
        } else {
            exe = "/bin/zsh"
            interpreterArgs = ["-n"]
        }

        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("envmanage_precheck_\(UUID().uuidString)")
        do {
            try content.write(to: tmp, atomically: true, encoding: .utf8)
        } catch { return }
        defer { try? FileManager.default.removeItem(at: tmp) }

        interpreterArgs.append(tmp.path)
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = interpreterArgs
        let err = Pipe()
        proc.standardError = err
        proc.standardOutput = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return // 检查器无法启动：不阻塞写入
        }
        if proc.terminationStatus != 0 {
            let data = err.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let brief = msg.components(separatedBy: .newlines).suffix(2).joined(separator: " / ")
            throw EditError("语法预检未通过，已拒绝写入以免破坏配置：\(brief.isEmpty ? "解析错误" : brief)")
        }
    }

    // MARK: - 管理员授权写入（F10-09 白名单护栏）

    private func adminWrite(content: String, to path: String) throws {
        guard WriteAudit.isAllowedSystemWrite(path) else {
            throw EditError("出于安全考虑，仅允许写入白名单内的系统 shell 配置文件；/etc/paths 等一律只读。")
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("envmanage_\(UUID().uuidString)")
        try content.write(to: tmp, atomically: true, encoding: .utf8)

        let cmd = "cp \(shq(tmp.path)) \(shq(path)) && chmod 644 \(shq(path))"
        let script = "do shell script \"\(cmd)\" with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let err = Pipe()
        proc.standardError = err
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            throw EditError("无法启动授权流程：\(error.localizedDescription)")
        }
        try? FileManager.default.removeItem(at: tmp)
        if proc.terminationStatus != 0 {
            let data = err.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8) ?? ""
            if msg.localizedCaseInsensitiveContains("cancel") || msg.contains("-128") {
                throw EditError("已取消管理员授权，未做修改。")
            }
            throw EditError("管理员写入失败或被取消。")
        }
    }

    private func shq(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
