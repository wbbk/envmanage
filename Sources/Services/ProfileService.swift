import Foundation

/// 一个环境变量 Profile 方案（F10-04）：用户级 export 变量的命名快照。
struct EnvProfile: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let createdAt: String
    /// 变量名 → 值（不含敏感变量的真实值以外内容；敏感值也原样保存在本机 JSON）。
    let vars: [String: String]
}

/// Profile 差异行（对比两个方案）。
struct ProfileDiffRow: Identifiable, Hashable {
    enum Kind: String { case added = "新增", removed = "缺失", changed = "值不同", same = "一致" }
    var id: String { name }
    let name: String
    let kind: Kind
    let leftValue: String?
    let rightValue: String?
}

/// Profile 方案服务：保存 / 列出 / 删除 / 对比 / 应用（逐项开关决定纳入哪些变量）。
/// 应用时把勾选的变量写入 ~/.zshrc 的 EnvManage Profile 受管区块，走 diff 预览确认。
final class ProfileService {

    static let markBegin = "# >>> EnvManage Profile >>>"
    static let markEnd = "# <<< EnvManage Profile <<<"

    private let store: FileStore

    init(store: FileStore) {
        self.store = store
    }

    var dir: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("EnvManage/Profiles").path
    }

    // MARK: - 保存与读取

    /// 以当前扫描到的用户级 export 变量创建一个方案（敏感变量可选排除）。
    @discardableResult
    func save(name: String, from entries: [EnvironmentVariable], includeSecrets: Bool) throws -> EnvProfile {
        let clean = name.trimmingCharacters(in: .whitespaces)
        guard !clean.isEmpty else { throw EditError("方案名不能为空。") }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var vars: [String: String] = [:]
        for e in entries where e.scope == .user && e.sourceType == .export && e.enabled {
            if !includeSecrets && e.isSensitive { continue }
            vars[e.name] = e.rawValue
        }
        guard !vars.isEmpty else { throw EditError("方案中没有可保存的变量。") }
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm"
        let profile = EnvProfile(name: clean, createdAt: fmt.string(from: Date()), vars: vars)
        let dict: [String: Any] = ["name": clean, "createdAt": profile.createdAt, "vars": vars]
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
        try String(data: data, encoding: .utf8)!.write(toFile: file(for: clean), atomically: true, encoding: .utf8)
        WriteAudit.log(action: "保存方案 \(clean)", file: file(for: clean), privileged: false, result: "成功")
        return profile
    }

    func list() -> [EnvProfile] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir) else { return [] }
        return names.filter { $0.hasSuffix(".json") }.compactMap { loadRaw($0) }.sorted { $0.name < $1.name }
    }

    func delete(name: String) {
        try? FileManager.default.removeItem(atPath: file(for: name))
    }

    private func file(for name: String) -> String {
        let safe = name.replacingOccurrences(of: "/", with: "_")
        return dir + "/" + safe + ".json"
    }

    private func loadRaw(_ fileName: String) -> EnvProfile? {
        let path = fileName.hasPrefix("/") ? fileName : dir + "/" + fileName
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let name = obj["name"] as? String,
              let created = obj["createdAt"] as? String,
              let vars = obj["vars"] as? [String: String]
        else { return nil }
        return EnvProfile(name: name, createdAt: created, vars: vars)
    }

    // MARK: - 对比

    static func diff(_ a: EnvProfile, _ b: EnvProfile) -> [ProfileDiffRow] {
        var rows: [ProfileDiffRow] = []
        let names = Set(a.vars.keys).union(b.vars.keys).sorted()
        for n in names {
            let av = a.vars[n], bv = b.vars[n]
            let kind: ProfileDiffRow.Kind
            if av == nil { kind = .added } else if bv == nil { kind = .removed }
            else { kind = av == bv ? .same : .changed }
            rows.append(ProfileDiffRow(name: n, kind: kind, leftValue: av, rightValue: bv))
        }
        return rows.filter { $0.kind != .same }
    }

    // MARK: - 应用（生成变更计划）

    /// 计划：把方案中被勾选（included）的变量写入 ~/.zshrc 的 Profile 受管区块。
    /// 区块外的同名定义保持不动，仅在预览 diff 中可见冲突。
    func planApply(profile: EnvProfile, included: Set<String>) throws -> FilePlan {
        let target = ShellFiles.defaultUserFile
        let before = store.read(target)
        var content = before
        // 清理旧 Profile 区块
        if let b = content.range(of: Self.markBegin),
           let e = content.range(of: Self.markEnd, range: b.upperBound..<content.endIndex) {
            content.removeSubrange(b.lowerBound..<e.upperBound)
        }
        content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let chosen = profile.vars.keys.filter { included.contains($0) }.sorted()
        if !chosen.isEmpty {
            var block = "\n\n" + Self.markBegin + "\n# 由 EnvManage Profile 应用生成，勿手动编辑本块\n"
            for n in chosen {
                let escaped = (profile.vars[n] ?? "").replacingOccurrences(of: "\"", with: "\\\"")
                block += "export \(n)=\"\(escaped)\"\n"
            }
            block += Self.markEnd
            content += block
        }
        let after = content.isEmpty ? "" : content + "\n"
        if after == before { throw EditError("区块内容没有变化。") }
        return FilePlan(path: target, before: before, after: after)
    }
}
