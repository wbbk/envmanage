import Foundation

/// 重复检测服务：找出被重复定义的变量，以及运行时 PATH 中的重复/失效目录。
/// 按 F05 给出细分类别（D01-D04/D06）与对应建议。
struct DuplicateService {

    func findDuplicates(grouped: [String: [EnvironmentVariable]],
                        runtimePath: String?) -> [DuplicateGroup] {
        var groups: [DuplicateGroup] = []

        for (name, entries) in grouped {
            let defs = entries.filter { $0.sourceType == .export }
            if name == "PATH" {
                let dupDirs = Self.pathDirDuplicates(runtimePath: runtimePath)
                if !dupDirs.isEmpty {
                    groups.append(DuplicateGroup(
                        name: "PATH", kind: .pathDir, category: .pathDir, definitions: defs, keepIndex: -1,
                        detail: dupDirs.joined(separator: "  ;  ")))
                }
                let stale = Self.stalePathDirs(runtimePath: runtimePath)
                if !stale.isEmpty {
                    groups.append(DuplicateGroup(
                        name: "PATH", kind: .pathDir, category: .stalePath, definitions: defs, keepIndex: -1,
                        detail: stale.joined(separator: "  ;  ")))
                }
            } else if defs.count > 1 {
                groups.append(DuplicateGroup(
                    name: name, kind: .scalar, category: Self.categorize(defs),
                    definitions: defs.sorted { $0.orderKey < $1.orderKey },
                    keepIndex: Self.chooseKeep(defs), detail: Self.evidence(defs)))
            }
        }
        return groups.sorted { $0.name < $1.name }
    }

    /// 细分类别：同文件多条 → D01；跨文件值全同 → D02；否则 D03。
    static func categorize(_ defs: [EnvironmentVariable]) -> DupCategory {
        if Set(defs.map { $0.source }).count == 1 { return .sameFile }
        if Set(defs.map { $0.rawValue }).count == 1 { return .sameValue }
        return .diffValue
    }

    /// 证据链：文件:行号 → 值（敏感值由展示层遮蔽，这里保留原文供定位）。
    static func evidence(_ defs: [EnvironmentVariable]) -> String {
        defs.map { "\($0.source):\($0.lineNo ?? 0)" }.joined(separator: "  →  ")
    }

    /// 运行时 PATH 中不存在/不可访问的目录（D06）。
    static func stalePathDirs(runtimePath: String?) -> [String] {
        guard let path = runtimePath else { return [] }
        let fm = FileManager.default
        return path.split(separator: ":").map(String.init).filter { dir in
            !dir.isEmpty && !fm.fileExists(atPath: dir)
        }.sorted()
    }

    /// 选择最终生效、建议保留的定义下标。
    ///
    /// shell 自上而下执行，同文件后写覆盖先写；跨文件后加载优先级更高。
    /// 排序键 (priority, lineNo) 取最大且处于启用状态者。
    static func chooseKeep(_ defs: [EnvironmentVariable]) -> Int {
        var best = 0
        var bestKey: (Int, Int)? = nil
        for (i, d) in defs.enumerated() {
            var key = d.orderKey
            if !d.enabled { key.0 -= 1000 }
            if bestKey == nil || key > bestKey! {
                bestKey = key
                best = i
            }
        }
        return best
    }

    /// 依据真实运行时 PATH 判断是否存在重复目录。
    static func pathDirDuplicates(runtimePath: String?) -> [String] {
        guard let path = runtimePath else { return [] }
        var seen = Set<String>()
        var dup = Set<String>()
        for d in path.split(separator: ":") {
            let s = String(d)
            if s.isEmpty { continue }
            if seen.contains(s) { dup.insert(s) }
            seen.insert(s)
        }
        return dup.sorted()
    }
}
