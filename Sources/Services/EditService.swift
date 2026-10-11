import Foundation

/// 编辑操作错误。
struct EditError: LocalizedError {
    let message: String
    init(_ m: String) { message = m }
    var errorDescription: String? { message }
}

/// 一份「文件变更计划」：路径 + 原内容 + 新内容（F02-07）。
/// 计划阶段纯计算不落盘，供 diff 预览确认后统一应用。
struct FilePlan {
    let path: String
    let before: String
    let after: String
}

/// 编辑服务：对环境变量配置文件进行 开关 / 改值 / 新增 / 删除 / 去重。
///
/// 每个操作提供两种形态：
/// - `planXxx`：只在内存中演算出 FilePlan，交给变更预览确认后 `apply` 落盘；
/// - 一步式（toggle/updateValue/…）：plan + apply，供无需预览的调用方（如 SelfTest）使用。
/// 所有落盘经由 `FileStore`：自动备份、撤销快照、外部修改校验、语法预检、审计日志。
final class EditService {

    private let store: FileStore

    init(store: FileStore) {
        self.store = store
    }

    // MARK: - 变更计划（纯计算，不落盘）

    /// 计划：切换某条 export 变量的生效状态。
    func planToggle(_ v: EnvironmentVariable, enable: Bool) throws -> FilePlan {
        guard v.sourceType == .export else {
            throw EditError("运行时与 /etc/paths 条目不支持开关，请直接编辑值。")
        }
        let lines = store.readLines(v.source)
        let idx = try Self.lineIndex(of: v, in: lines)
        var newLines = lines
        let original = lines[idx]
        let indent = String(original.prefix(while: { $0 == " " || $0 == "\t" }))
        let body = original.trimmingCharacters(in: .whitespaces)
        let marker = AppInfo.disableMarker

        if enable {
            if body.hasPrefix(marker) {
                let restored = String(body.dropFirst(marker.count))
                    .trimmingCharacters(in: .whitespaces)
                newLines[idx] = indent + restored
            }
        } else {
            if !body.hasPrefix(marker) {
                newLines[idx] = marker + " " + body
            }
        }
        return FilePlan(path: v.source, before: store.read(v.source), after: Self.join(newLines))
    }

    /// 计划：修改一条 export 变量的值。
    func planUpdateValue(_ v: EnvironmentVariable, newValue: String) throws -> FilePlan {
        guard v.sourceType == .export else {
            throw EditError("只能修改 shell 配置文件中的 export 条目。")
        }
        let lines = store.readLines(v.source)
        let idx = try Self.lineIndex(of: v, in: lines)
        try Self.requireSafeEditable(lines[idx], name: v.name)
        var newLines = lines

        let original = lines[idx]
        let indent = String(original.prefix(while: { $0 == " " || $0 == "\t" }))
        var body = original.trimmingCharacters(in: .whitespaces)
        if body.hasPrefix(AppInfo.disableMarker) {
            body = String(body.dropFirst(AppInfo.disableMarker.count)).trimmingCharacters(in: .whitespaces)
        }
        let isExport = body.hasPrefix("export ")
        let prefix = isExport ? "export " : ""
        let rest = isExport ? String(body.dropFirst("export ".count)) : body
        guard rest.contains("=") else { throw EditError("该行不是有效的变量赋值。") }
        let name = rest.components(separatedBy: "=")[0]
        let escaped = newValue.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        newLines[idx] = "\(indent)\(prefix)\(name)=\"\(escaped)\""
        return FilePlan(path: v.source, before: store.read(v.source), after: Self.join(newLines))
    }

    /// 计划：删除一条定义行。
    func planRemove(_ v: EnvironmentVariable) throws -> FilePlan {
        guard v.sourceType == .export else {
            throw EditError("运行时与 /etc/paths 条目不能删除定义行。")
        }
        let lines = store.readLines(v.source)
        let idx = try Self.lineIndex(of: v, in: lines)
        try Self.requireSafeEditable(lines[idx], name: v.name)
        var newLines = lines
        newLines.remove(at: idx)
        return FilePlan(path: v.source, before: store.read(v.source), after: Self.join(newLines))
    }

    /// 计划：新增一个变量到合适文件末尾。
    func planAdd(name: String, value: String, user: Bool) throws -> FilePlan {
        let target = user ? ShellFiles.defaultUserFile : ShellFiles.defaultSystemFile
        var lines = FileManager.default.fileExists(atPath: target) ? store.readLines(target) : []
        let before = FileManager.default.fileExists(atPath: target) ? store.read(target) : ""
        if lines.last == "" { lines.removeLast() }
        lines.append("")
        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        lines.append("export \(name)=\"\(escaped)\"")
        return FilePlan(path: target, before: before, after: Self.join(lines))
    }

    /// 计划：对一组重复定义执行去重（保留 keepIndex，禁用或删除其余），按文件产出多份计划。
    func planDedupe(group: DuplicateGroup, disable: Bool) throws -> [FilePlan] {
        var extras: [EnvironmentVariable] = []
        for (i, d) in group.definitions.enumerated() where i != group.keepIndex {
            extras.append(d)
        }
        guard !extras.isEmpty else { throw EditError("该组没有需要处理的多余定义。") }

        var plans: [FilePlan] = []
        for file in Set(extras.map(\.source)).sorted() {
            let ofFile = extras.filter { $0.source == file }
            let before = store.read(file)
            var lines = store.readLines(file)
            if disable {
                for d in ofFile.sorted(by: { ($0.lineNo ?? 0) < ($1.lineNo ?? 0) }) where d.enabled {
                    guard d.sourceType == .export,
                          let idx = (d.lineNo.map { $0 - 1 }), idx >= 0, idx < lines.count
                    else { continue }
                    let body = lines[idx].trimmingCharacters(in: .whitespaces)
                    if !body.hasPrefix(AppInfo.disableMarker) {
                        lines[idx] = AppInfo.disableMarker + " " + body
                    }
                }
            } else {
                // 删除会使同文件后续行号错位，故按行号倒序删除。
                for d in ofFile.sorted(by: { ($0.lineNo ?? 0) > ($1.lineNo ?? 0) }) {
                    guard d.sourceType == .export,
                          let idx = (d.lineNo.map { $0 - 1 }), idx >= 0, idx < lines.count
                    else { continue }
                    try Self.requireSafeEditable(lines[idx], name: d.name)
                    lines.remove(at: idx)
                }
            }
            let after = Self.join(lines)
            if after != before {
                plans.append(FilePlan(path: file, before: before, after: after))
            }
        }
        if plans.isEmpty {
            throw EditError("没有需要变更的内容（多余定义可能已经处于禁用状态）。")
        }
        return plans
    }

    /// 应用一组变更计划：单一事务，全部落盘、可整体撤销。
    func apply(_ plans: [FilePlan], label: String) throws {
        try store.transaction(label) {
            for p in plans {
                try store.write(content: p.after, to: p.path)
            }
        }
    }

    // MARK: - 一步式操作（plan + apply）

    @discardableResult
    func toggle(_ v: EnvironmentVariable, enable: Bool) throws -> String {
        let p = try planToggle(v, enable: enable)
        try apply([p], label: (enable ? "启用 " : "禁用 ") + v.name)
        return v.source
    }

    @discardableResult
    func updateValue(_ v: EnvironmentVariable, newValue: String) throws -> String {
        let p = try planUpdateValue(v, newValue: newValue)
        try apply([p], label: "编辑 \(v.name)")
        return v.source
    }

    @discardableResult
    func remove(_ v: EnvironmentVariable) throws -> String {
        let p = try planRemove(v)
        try apply([p], label: "删除 \(v.name)")
        return v.source
    }

    @discardableResult
    func add(name: String, value: String, user: Bool) throws -> String {
        let p = try planAdd(name: name, value: value, user: user)
        try apply([p], label: "新增 \(name)")
        return p.path
    }

    /// 成组去重（一步式）。返回受影响文件数。
    @discardableResult
    func dedupe(group: DuplicateGroup, disable: Bool) throws -> Int {
        let ps = try planDedupe(group: group, disable: disable)
        try apply(ps, label: "去重 \(group.name)")
        return ps.count
    }

    // MARK: - 安全护栏与工具

    /// 危险行拒绝原位改删：含逻辑/管道/命令替换/控制流片段的行不是简单赋值，
    /// 原位修改或删除可能破坏脚本逻辑（宁可误判，保守拒绝）。
    static func requireSafeEditable(_ line: String, name: String) throws {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let body = trimmed.hasPrefix(AppInfo.disableMarker)
            ? String(trimmed.dropFirst(AppInfo.disableMarker.count)).trimmingCharacters(in: .whitespaces)
            : trimmed
        let dangerous = ["&&", "||", ";", "|", "`", "$(", "eval", "<<", "then", "fi", "if "]
        if dangerous.contains(where: { body.contains($0) }) {
            throw EditError("该行不是简单赋值语句（含逻辑/控制/命令替换片段），拒绝原位改删：\(name)。")
        }
    }

    /// 校验并按 1 基行号取索引。
    static func lineIndex(of v: EnvironmentVariable, in lines: [String]) throws -> Int {
        let idx = (v.lineNo ?? 0) - 1
        guard idx >= 0, idx < lines.count else { throw EditError("行号越界，请刷新后重试。") }
        return idx
    }

    /// 行数组重组为文本（以 \n 连接，末尾补一个换行）。
    static func join(_ lines: [String]) -> String {
        lines.joined(separator: "\n") + "\n"
    }
}
