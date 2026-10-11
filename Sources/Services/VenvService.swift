import Foundation

/// 虚拟环境（venv）管理服务（F06-09）：
/// 用检测到的 Python 创建 venv，并删除已存在的 venv 目录（含二次确认，由 UI 负责）。
enum VenvService {

    /// 一个已发现的虚拟环境。
    struct Info: Identifiable, Hashable {
        var id: String { path }
        let path: String        // venv 根目录
        let pythonVersion: String?
    }

    /// 创建 venv：`<python> -m venv <path>`，输出流式回调。
    static func create(pythonExe: String, path: String,
                       onLine: @escaping (String) -> Void,
                       onDone: @escaping (Int32) -> Void) {
        let expanded = (path as NSString).expandingTildeInPath
        let fm = FileManager.default
        if fm.fileExists(atPath: expanded) {
            onLine("❌ 目标目录已存在：\(expanded)")
            onDone(-1)
            return
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonExe)
        proc.arguments = ["-m", "venv", expanded]
        stream(proc, onLine: onLine, onDone: onDone)
    }

    /// 读取某 venv 的元信息与 Python 版本。
    static func inspect(path: String) -> Info? {
        let cfg = (path as NSString).appendingPathComponent("pyvenv.cfg")
        guard FileManager.default.fileExists(atPath: cfg),
              let content = try? String(contentsOfFile: cfg, encoding: .utf8)
        else { return nil }
        var version: String? = nil
        for line in content.components(separatedBy: .newlines) {
            let parts = line.split(separator: "=", omittingEmptySubsequences: true)
            if parts.count == 2 {
                let k = parts[0].trimmingCharacters(in: .whitespaces)
                let v = parts[1].trimmingCharacters(in: .whitespaces)
                if k == "version" || k == "python" || k == "version-info" { version = v; break }
            }
        }
        return Info(path: path, pythonVersion: version)
    }

    /// 删除 venv 目录（仅限包含 pyvenv.cfg 的目录，防误删）。
    static func delete(path: String) throws {
        let expanded = (path as NSString).expandingTildeInPath
        guard inspect(path: expanded) != nil else {
            throw EditError("目标不是有效的 venv（缺少 pyvenv.cfg），拒绝删除：\(expanded)")
        }
        do {
            try FileManager.default.removeItem(atPath: expanded)
            WriteAudit.log(action: "删除 venv", file: expanded, privileged: false, result: "成功")
        } catch {
            throw EditError("删除失败：\(error.localizedDescription)")
        }
    }

    /// 常用项目目录下的一层/两层浅扫描，发现已有的 venv。
    static func discover(near home: String = NSHomeDirectory()) -> [Info] {
        let fm = FileManager.default
        let roots = ["code", "code-project", "projects", "Documents", "Desktop", "src", "work"]
            .map { home + "/" + $0 }
        var results: [Info] = []
        var seen = Set<String>()
        for root in roots where fm.fileExists(atPath: root) {
            // root/*/.venv 与 root/*/*/… 只扫两层，避免全盘遍历
            if let level1 = try? fm.contentsOfDirectory(atPath: root) {
                for a in level1.prefix(120) {
                    let p1 = root + "/" + a
                    for name in [".venv", "venv", "env", ".env"] {
                        let candidate = p1 + "/" + name
                        if seen.insert(candidate).inserted, inspect(path: candidate) != nil {
                            results.append(inspect(path: candidate)!)
                        }
                    }
                    if let level2 = try? fm.contentsOfDirectory(atPath: p1) {
                        for b in level2.prefix(60) {
                            for name in [".venv", "venv"] {
                                let candidate = p1 + "/" + b + "/" + name
                                if seen.insert(candidate).inserted, inspect(path: candidate) != nil {
                                    results.append(inspect(path: candidate)!)
                                }
                            }
                        }
                    }
                }
            }
        }
        return results.sorted { $0.path < $1.path }
    }

    private static func stream(_ proc: Process, onLine: @escaping (String) -> Void,
                               onDone: @escaping (Int32) -> Void) {
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = out
        out.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            if data.isEmpty { return }
            if let s = String(data: data, encoding: .utf8) {
                for line in s.components(separatedBy: .newlines) where !line.isEmpty {
                    onLine(line)
                }
            }
        }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try proc.run()
                proc.waitUntilExit()
                let code = proc.terminationStatus
                DispatchQueue.main.async { onDone(code) }
            } catch {
                DispatchQueue.main.async {
                    onLine("❌ 无法启动：\(error.localizedDescription)")
                    onDone(-127)
                }
            }
        }
    }
}
