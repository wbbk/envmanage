import Foundation

/// PATH 管理服务：基于真实运行时 PATH 生成有序目录列表，校验目录是否存在，
/// 并标注每个目录来自系统还是用户。
struct PathService {

    private let scanner = ShellConfigService()

    func buildEntries() -> [PathEntry] {
        guard let runtimePath = ProcessInfo.processInfo.environment["PATH"],
              !runtimePath.isEmpty else { return [] }

        // 收集来自 /etc/paths 系列的系统目录集合
        var systemDirs = Set<String>()
        for e in scanner.parsePathsFiles() {
            systemDirs.insert(e.rawValue)
        }

        let fm = FileManager.default
        var entries: [PathEntry] = []
        var seen = Set<String>()
        for (order, raw) in runtimePath.split(separator: ":", omittingEmptySubsequences: false).enumerated() {
            let dir = String(raw)
            if dir.isEmpty { continue }
            let exists = fm.fileExists(atPath: dir)
            let scope: EnvScope = systemDirs.contains(dir) ? .system : .user
            entries.append(PathEntry(directory: dir, exists: exists,
                                     scope: scope, order: order))
            seen.insert(dir)
        }
        return entries
    }

    /// 重复目录（依据运行时 PATH）。
    func duplicateDirectories() -> [String] {
        DuplicateService.pathDirDuplicates(runtimePath: ProcessInfo.processInfo.environment["PATH"])
    }
}
