import Foundation

/// 写操作审计日志（F10-09）：所有落盘操作记录到本地 jsonl，
/// 含时间、动作、目标文件、是否提权、结果。敏感值不进入日志（只记文件与动作）。
enum WriteAudit {

    static var logURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("EnvManage/Audit/operations.jsonl")
    }

    /// 系统文件可写白名单（F10-09）：仅允许受管的可编辑系统 shell 文件；
    /// /etc/paths* 一律拒绝写入。
    static let systemWriteWhitelist: Set<String> = [
        "/etc/zshenv", "/etc/zprofile", "/etc/zshrc", "/etc/profile",
    ]

    static func isAllowedSystemWrite(_ path: String) -> Bool {
        systemWriteWhitelist.contains(path)
    }

    /// 追加一条审计记录（失败静默，不影响主流程）。
    static func log(action: String, file: String, privileged: Bool, result: String) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let entry: [String: String] = [
            "time": fmt.string(from: Date()),
            "action": action,
            "file": file.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
            "privileged": privileged ? "1" : "0",
            "result": result,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: entry),
              var line = String(data: data, encoding: .utf8) else { return }
        line += "\n"
        let fm = FileManager.default
        try? fm.createDirectory(at: logURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if let fh = try? FileHandle(forWritingTo: logURL) {
            defer { try? fh.close() }
            fh.seekToEndOfFile()
            fh.write(Data(line.utf8))
        } else {
            try? line.write(to: logURL, atomically: true, encoding: .utf8)
        }
    }

    /// 读取最近 N 条审计记录（设置页展示用）。
    static func recent(_ limit: Int = 50) -> [[String: String]] {
        guard let content = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        let lines = content.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return lines.suffix(limit).reversed().compactMap { line in
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
            else { return nil }
            return obj
        }
    }
}
