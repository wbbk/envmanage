import Foundation

/// 命令在 PATH 中的一个命中位置。
struct CommandHit: Identifiable {
    let id = UUID()
    let path: String          // 完整可执行路径，如 /opt/homebrew/bin/python3
    let dir: String           // 所在 PATH 目录
    let order: Int            // 在 PATH 中的序号（0 起，越小越优先）
    let isSymlink: Bool
    let realpath: String      // 解析符号链接后的真实路径
    let exists: Bool
    let executable: Bool
}

/// 一次命令解析结果（F04-06 命令查找器）。
struct CommandResolution: Identifiable {
    let id = UUID()
    let command: String
    let hits: [CommandHit]
    let pathDirs: [String]

    /// 实际会执行的第一个有效命中。
    var firstHit: CommandHit? { hits.first { $0.exists && $0.executable } }

    /// 被更高优先级同名命令遮蔽的命中（shell 里 `type -a` 视角）。
    var shadowed: [CommandHit] {
        guard let first = firstHit else { return hits }
        return hits.filter { $0.id != first.id }
    }

    /// 是否存在多个来源（遮蔽风险）。
    var hasShadowing: Bool { hits.filter { $0.exists && $0.executable }.count > 1 }
}

/// 命令查找器：给定命令名，在生效 PATH 上按序解析全部命中，标注第一命中、
/// 符号链接解析链与被遮蔽项，回答「为什么我执行的不是这个」。
enum CommandResolver {

    static func resolve(_ command: String, pathValue: String? = nil) -> CommandResolution {
        let raw = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = pathValue ?? ProcessInfo.processInfo.environment["PATH"] ?? ""
        let dirs = path.split(separator: ":").map(String.init)
        let fm = FileManager.default
        var hits: [CommandHit] = []

        for (idx, dir) in dirs.enumerated() {
            let dirPath = dir.isEmpty ? "." : dir
            let cand = dirPath + "/" + raw
            let exists = fm.fileExists(atPath: cand)
            let exec = fm.isExecutableFile(atPath: cand)
            // 仅把「存在且可执行」的候选计为命中
            guard exists, exec else { continue }
            // 用 lstat 判断是否符号链接（attributesOfItem 会跟随链接）
            var st = stat()
            let isLink = lstat(cand, &st) == 0 && (st.st_mode & S_IFMT) == S_IFLNK
            let real = (cand as NSString).resolvingSymlinksInPath
            hits.append(CommandHit(path: cand, dir: dirPath, order: idx,
                                   isSymlink: isLink, realpath: real,
                                   exists: exists, executable: exec))
        }
        return CommandResolution(command: raw, hits: hits, pathDirs: dirs)
    }
}
