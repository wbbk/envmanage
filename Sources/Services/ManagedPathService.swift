import Foundation

/// 受管 PATH 条目服务（F04-03）：在 ~/.zshrc 用受管区块实现用户级 PATH 目录的
/// 新增 / 删除 / 上下移动排序。区块格式：
///
///   # >>> EnvManage PATH >>>
///   export PATH="dir1:dir2:$PATH"
///   # <<< EnvManage PATH <<<
///
/// 所有变更以 FilePlan 形式产出，走统一的 diff 预览确认后才落盘。
final class ManagedPathService {

    static let markBegin = "# >>> EnvManage PATH >>>"
    static let markEnd = "# <<< EnvManage PATH <<<"

    private let store: FileStore

    init(store: FileStore) {
        self.store = store
    }

    /// 受管区块所在文件（用户级默认 ~/.zshrc）。
    var file: String { ShellFiles.defaultUserFile }

    /// 读取当前受管 PATH 条目（保持顺序；无区块时为空）。
    func load() -> [String] {
        let content = store.read(file)
        guard let b = content.range(of: Self.markBegin),
              let e = content.range(of: Self.markEnd, range: b.upperBound..<content.endIndex)
        else { return [] }
        let block = String(content[b.upperBound..<e.lowerBound])
        for line in block.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("export PATH=") {
                var v = String(t.dropFirst("export PATH=".count))
                if v.hasPrefix("\"") { v.removeFirst() }
                if v.hasSuffix("\"") { v.removeLast() }
                // 去掉追加占位符，仅保留受管目录
                v = v.replacingOccurrences(of: ":$PATH", with: "")
                    .replacingOccurrences(of: ":${PATH}", with: "")
                return v.split(separator: ":", omittingEmptySubsequences: true).map(String.init)
            }
        }
        return []
    }

    /// 生成变更计划：把受管区块改写为给定条目（顺序即生效优先级，靠前高）。
    /// 传入空数组表示移除整个区块。含危险字符的目录拒绝写入。
    func plan(_ entries: [String]) throws -> FilePlan {
        for dir in entries {
            let banned = ["\"", "'", "`", "$", "\\", ";", "&", "|", "\n", "\r"]
            if dir.isEmpty || banned.contains(where: { dir.contains($0) }) {
                throw EditError("PATH 目录含非法字符，已拒绝：\(dir.prefix(40))")
            }
        }
        let before = store.read(file)
        var content = before
        if let b = content.range(of: Self.markBegin),
           let e = content.range(of: Self.markEnd, range: b.upperBound..<content.endIndex) {
            // 连同区块前的空行一并清理
            var start = b.lowerBound
            let preceding = content[content.startIndex..<start]
            if preceding.hasSuffix("\n\n") {
                start = content.index(after: content.index(before: start))
            }
            content.removeSubrange(start..<e.upperBound)
        }
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !entries.isEmpty {
            let line = "export PATH=\"" + entries.joined(separator: ":") + ":$PATH\""
            content += "\n\n" + Self.markBegin + "\n# 由 EnvManage 管理，勿手动编辑本块\n"
                + line + "\n" + Self.markEnd
        }
        let after = content.isEmpty ? "" : content + "\n"
        return FilePlan(path: file, before: before, after: after)
    }
}
