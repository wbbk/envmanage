import Foundation

/// 一条受管 GUI（launchd）环境变量。
struct GuiEnvEntry: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let value: String
    /// launchctl 当前会话中的实际值（可能与受管清单不一致）。
    let liveValue: String?
    /// 是否已与当前 GUI 会话一致。
    var inSync: Bool { liveValue == value }
}

/// GUI 环境变量受管服务（F10-01）：
/// macOS 的 GUI 应用不读取 shell 配置，其环境来自 launchd 会话。
/// 本服务把受管变量持久化到 Application Support，并用 `launchctl setenv/unsetenv`
/// 应用到当前 GUI 会话；应用启动时自动重放（系统重启后需再次打开 EnvManage 重放）。
final class GuiEnvService {

    private let store: FileStore

    init(store: FileStore) {
        self.store = store
    }

    /// 受管清单文件（JSON），写入走 FileStore 流水线因此享受备份/撤销/审计。
    var file: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("EnvManage/GuiEnv/gui-env.json").path
    }

    // MARK: - 读取

    /// 受管清单 + 当前 launchctl 实际值对照。
    func entries() -> [GuiEnvEntry] {
        let dict = loadDict()
        return dict.keys.sorted().map { name in
            GuiEnvEntry(name: name, value: dict[name] ?? "", liveValue: liveValue(of: name))
        }
    }

    private func loadDict() -> [String: String] {
        let content = store.read(file)
        guard let data = content.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        else { return [:] }
        return obj
    }

    /// `launchctl getenv NAME` 读取当前 GUI 会话值（未设置返回 nil）。
    func liveValue(of name: String) -> String? {
        let out = Self.run("/bin/launchctl", ["getenv", name])
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - 变更计划（复用 FilePlan 预览流）

    /// 计划：新增或修改一个 GUI 变量。
    func planSet(name: String, value: String) throws -> FilePlan {
        try Self.requireValidName(name)
        if value.contains("\n") || value.contains("\r") {
            throw EditError("GUI 变量值不能包含换行。")
        }
        var dict = loadDict()
        dict[name] = value
        return Self.makePlan(file: file, store: store, dict: dict)
    }

    /// 计划：移除一个 GUI 变量。
    func planRemove(name: String) throws -> FilePlan {
        var dict = loadDict()
        guard dict[name] != nil else { throw EditError("该变量不在受管清单中。") }
        dict[name] = nil
        return Self.makePlan(file: file, store: store, dict: dict)
    }

    private static func makePlan(file: String, store: FileStore, dict: [String: String]) -> FilePlan {
        let before = store.read(file)
        let data = (try? JSONSerialization.data(withJSONObject: dict,
                                                options: [.prettyPrinted, .sortedKeys])) ?? Data()
        let after = String(data: data, encoding: .utf8) ?? "{}\n"
        return FilePlan(path: file, before: before, after: after.hasSuffix("\n") ? after : after + "\n")
    }

    /// 变量名合法性：仅字母/数字/下划线，且不以数字开头。
    static func requireValidName(_ name: String) throws {
        let ok = !name.isEmpty && name.range(
            of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil
        if !ok {
            throw EditError("变量名只允许字母、数字、下划线（不能以数字开头）：\(name)")
        }
    }

    // MARK: - 应用到 launchd（计划确认后的副作用）

    /// 把变量设置到当前 GUI 会话。
    func applySet(name: String, value: String) {
        _ = Self.run("/bin/launchctl", ["setenv", name, value])
    }

    /// 从当前 GUI 会话移除变量。
    func applyUnset(name: String) {
        _ = Self.run("/bin/launchctl", ["unsetenv", name])
    }

    /// 应用启动时重放受管清单（系统重启后 launchd 变量会丢失）。
    func replayOnStartup() {
        for (name, value) in loadDict() {
            if liveValue(of: name) != value {
                _ = Self.run("/bin/launchctl", ["setenv", name, value])
            }
        }
    }

    @discardableResult
    private static func run(_ exe: String, _ args: [String]) -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = args
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch { return "" }
        return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
