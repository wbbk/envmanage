import Foundation

/// 备份服务：任何写操作前把原文件复制到
/// `~/Library/Application Support/EnvManage/Backups`，每个文件保留最近 10 份。
struct BackupService {

    /// 备份指定文件，返回备份文件 URL（失败返回 nil，但不阻断主流程）。
    @discardableResult
    func backup(_ path: String) -> URL? {
        let fm = FileManager.default
        let dir = AppInfo.backupDir
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let src = URL(fileURLWithPath: path)
        let baseName = src.deletingPathExtension().lastPathComponent
        let ext = src.pathExtension
        let stamp = Self.formatter.string(from: Date())
        let name = ext.isEmpty ? "\(baseName).\(stamp).bak" : "\(baseName).\(stamp).\(ext).bak"
        let dest = dir.appendingPathComponent(name)

        guard fm.fileExists(atPath: path) else { return nil }
        do {
            try fm.copyItem(atPath: path, toPath: dest.path)
            prune(baseName: baseName, in: dir)
            return dest
        } catch {
            return nil
        }
    }

    /// 列出某原始文件名的历史备份（按时间倒序）。
    func backups(for path: String) -> [URL] {
        let fm = FileManager.default
        let baseName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        guard let items = try? fm.contentsOfDirectory(at: AppInfo.backupDir,
                                                      includingPropertiesForKeys: [.creationDateKey]) else {
            return []
        }
        return items.filter { $0.lastPathComponent.hasPrefix(baseName + ".") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// 只保留每个文件最近 10 份备份。
    private func prune(baseName: String, in dir: URL) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        let related = items.filter { $0.lastPathComponent.hasPrefix(baseName + ".") }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in related.dropFirst(10) {
            try? fm.removeItem(at: old)
        }
    }

    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
