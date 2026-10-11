import Foundation
import Combine

/// 全局视图模型：持有服务与界面状态，协调扫描与所有编辑操作。
final class EnvManagerViewModel: ObservableObject {

    // MARK: - 服务

    let store: FileStore
    let undo: FileSnapshotUndoManager
    let edit: EditService
    let runtime: RuntimeService
    private let scanner = ShellConfigService()
    private let dup = DuplicateService()
    private let pathService = PathService()
    let managedPath: ManagedPathService
    let launchEnv: GuiEnvService
    let profileSvc: ProfileService

    // MARK: - 状态

    @Published var entries: [EnvironmentVariable] = []
    @Published var duplicates: [DuplicateGroup] = []
    @Published var runtimes: [RuntimeInstall] = []
    @Published var pathEntries: [PathEntry] = []
    /// 受管 PATH 条目（F04-03，~/.zshrc 受管区块，顺序即优先级）。
    @Published var managedPathEntries: [String] = []
    /// 受管 GUI（launchd）环境变量（F10-01）。
    @Published var guiEnvEntries: [GuiEnvEntry] = []
    /// GUI vs Shell 环境差异（F10-02）。
    @Published var envDiffRows: [EnvDiffRow] = []
    /// 审计日志最近记录（F10-09）。
    @Published var auditLog: [[String: String]] = []
    /// Profile 方案列表（F10-04）。
    @Published var profiles: [EnvProfile] = []
    /// 工具链只读检测结果（F10-08）。
    @Published var toolboxes: [ToolboxTool] = []
    /// 发现的虚拟环境（F06-09）。
    @Published var venvs: [VenvService.Info] = []
    /// 项目环境文件扫描结果（F10-03）。
    @Published var projectEnvFiles: [ProjectEnvFile] = []
    @Published var projectDir: String = ""

    @Published var scopeFilter: EnvScope? = nil       // nil = 全部
    @Published var runtimeFilter: RuntimeLanguage? = nil  // nil = 全部语言
    @Published var searchText: String = ""
    @Published var statusMessage: String = "就绪"
    @Published var isBusy = false

    // 展示选项
    @Published var revealSecrets = false      // F02-06 敏感值是否明文展示
    @Published var groupByName = false         // F01-04 按名称聚合视图
    @Published var selectedID: String? = nil   // 右侧详情面板选中项

    // 命令查找器（F04-06）
    @Published var finderCommand: String = ""
    @Published var finderResult: CommandResolution?

    // 变更预览（F02-07）：待确认的写操作计划；after 为确认后的副作用（如 launchctl 同步）
    struct PendingChange: Identifiable {
        let id = UUID()
        let label: String
        let plans: [FilePlan]
        var after: (() -> Void)? = nil
    }
    @Published var pendingChange: PendingChange? = nil

    // 写入结果分类（F07）
    enum WriteOutcome: Equatable {
        case savedNewShell(String)      // 已保存，需新 Shell 验证
        case confirmedRuntime(String)   // 已与运行时采样一致
        case failed(String)             // 失败/被拒绝
    }
    @Published var lastOutcome: WriteOutcome? = nil

    // 忽略此类重复提醒（F05），持久化
    @Published var ignoredDupNames: Set<String> = [] {
        didSet { UserDefaults.standard.set(Array(ignoredDupNames), forKey: "EnvManage.ignoredDuplicates") }
    }

    // 安装会话（RuntimeManagerView 的安装弹窗使用）
    @Published var installLog: String = ""
    @Published var isInstalling = false

    /// 存在重复定义的变量名集合（用于主表格高亮）。
    var duplicateNames: Set<String> { Set(duplicates.map { $0.name }) }

    /// 某变量在当前进程的实际生效情况分类（F07 生效确认）。
    func confirmation(of v: EnvironmentVariable) -> String {
        guard v.sourceType == .export || v.sourceType == .fish else {
            return v.sourceType == .runtime ? "运行时快照，仅供对照" : "系统只读项，仅供对照"
        }
        if !v.enabled {
            return effectiveValue(of: v.name) == nil ? "已禁用，且无其他来源生效" : "已禁用，但可能仍被其他来源提供"
        }
        guard let eff = effectiveValue(of: v.name) else { return "当前进程未见此变量 — 待新 Shell 验证" }
        // 同名后定义可能覆盖：若存在更高优先级的启用定义则仍被覆盖
        let supers = definitions(named: v.name).first {
            $0.id != v.id && $0.enabled && $0.orderKey > v.orderKey
        }
        if supers != nil { return "仍被更高优先级的同名定义覆盖" }
        return eff == v.rawValue ? "已与当前进程采样确认一致" : "与当前进程值不同 — 可能被动态因素改变"
    }

    // MARK: - 初始化

    init() {
        let s = FileStore()
        let u = FileSnapshotUndoManager { path, content in
            try s.applyWrite(content: content, to: path)
        }
        s.undo = u
        self.store = s
        self.undo = u
        self.edit = EditService(store: s)
        self.runtime = RuntimeService(store: s)
        self.managedPath = ManagedPathService(store: s)
        self.launchEnv = GuiEnvService(store: s)
        self.profileSvc = ProfileService(store: s)
        self.ignoredDupNames = Set(UserDefaults.standard.stringArray(forKey: "EnvManage.ignoredDuplicates") ?? [])
    }

    // MARK: - 派生数据

    /// 依据作用域筛选与搜索词过滤后的可见条目。
    var visibleEntries: [EnvironmentVariable] {
        entries.filter { e in
            (scopeFilter == nil || e.scope == scopeFilter) &&
            (searchText.isEmpty ||
             e.name.localizedCaseInsensitiveContains(searchText) ||
             e.rawValue.localizedCaseInsensitiveContains(searchText))
        }
        .sorted {
            if $0.name != $1.name { return $0.name < $1.name }
            return $0.orderKey < $1.orderKey
        }
    }

    var counts: [EnvScope: Int] {
        var c: [EnvScope: Int] = [.system: 0, .user: 0, .runtime: 0]
        for e in entries { c[e.scope, default: 0] += 1 }
        return c
    }

    /// 按语言筛选后的运行时列表。
    var visibleRuntimes: [RuntimeInstall] {
        guard let f = runtimeFilter else { return runtimes }
        return runtimes.filter { $0.language == f }
    }

    /// 当前选中的变量（供详情面板）。
    var selectedVariable: EnvironmentVariable? {
        guard let id = selectedID else { return nil }
        return entries.first { $0.id == id }
    }

    /// 与某变量同名的全部定义，按加载优先级/行号排序（覆盖链）。
    func definitions(named name: String) -> [EnvironmentVariable] {
        entries.filter { $0.name == name }
            .sorted { $0.orderKey < $1.orderKey }
    }

    /// 某变量在当前进程的真实生效值（仅运行时快照可见）。
    func effectiveValue(of name: String) -> String? {
        scanner.effectiveValue(of: name)
    }

    /// 命令查找：解析命令名在生效 PATH 上的全部命中。
    func runCommandFinder() {
        let cmd = finderCommand.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { finderResult = nil; return }
        finderResult = CommandResolver.resolve(cmd)
    }

    /// 选中并高亮某变量（供命令查找器回跳）。
    func select(_ v: EnvironmentVariable) { selectedID = v.id }

    // MARK: - 扫描

    func refresh() {
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let scanned = self.scanner.scanAll()
            let grouped = self.scanner.groupByName(scanned)
            let runtimePath = self.scanner.effectiveValue(of: "PATH")
            var dupes = self.dup.findDuplicates(grouped: grouped, runtimePath: runtimePath)
            dupes.removeAll { self.ignoredDupNames.contains($0.name + "#" + $0.category.rawValue) }
            let pathList = self.pathService.buildEntries()
            let runtimes = self.runtime.detectAll()
            // F08：登记扫描基线哈希，供写入前外部修改校验
            self.store.markScanned(paths: scanned.filter { $0.sourceType != .runtime }.map { $0.source })
            DispatchQueue.main.async {
                self.entries = scanned
                self.duplicates = dupes
                self.pathEntries = pathList
                self.runtimes = runtimes
                self.managedPathEntries = self.managedPath.load()
                self.guiEnvEntries = self.launchEnv.entries()
                self.profiles = self.profileSvc.list()
                self.toolboxes = ToolboxService.detect()
                self.isBusy = false
                self.statusMessage = "已刷新：\(scanned.count) 条记录 · \(dupes.count) 组重复 · \(runtimes.count) 个运行时"
            }
        }
    }

    // MARK: - 操作（均先生成变更计划→预览确认→再落盘，F02-07）

    /// 统一入口：计算计划并弹出预览；after 在应用成功后执行。
    private func requestChange(_ label: String, after: (() -> Void)? = nil,
                               _ plan: () throws -> [FilePlan]) {
        do {
            let plans = try plan()
            if plans.isEmpty {
                statusMessage = "无需变更：\(label)"
                return
            }
            pendingChange = PendingChange(label: label, plans: plans, after: after)
        } catch let e as EditError {
            lastOutcome = .failed(e.message)
            statusMessage = "⚠️ " + e.message
        } catch {
            lastOutcome = .failed(error.localizedDescription)
            statusMessage = "⚠️ " + error.localizedDescription
        }
    }

    /// 预览弹窗中点「应用变更」。
    func confirmPendingChange() {
        guard let pc = pendingChange else { return }
        pendingChange = nil
        do {
            try edit.apply(pc.plans, label: pc.label)
            pc.after?()
            if pc.after != nil {
                lastOutcome = .confirmedRuntime(pc.label)
                statusMessage = "✅ \(pc.label) 已保存并应用到当前 GUI 会话（⌘Z 可撤销）"
            } else {
                lastOutcome = .savedNewShell(pc.label)
                statusMessage = "✅ \(pc.label) 已保存 — 新开终端后生效（⌘Z 可撤销）"
            }
            refresh()
        } catch let e as EditError {
            lastOutcome = .failed(e.message)
            statusMessage = "⚠️ " + e.message
        } catch {
            lastOutcome = .failed(error.localizedDescription)
            statusMessage = "⚠️ " + error.localizedDescription
        }
    }

    func cancelPendingChange() {
        pendingChange = nil
        statusMessage = "已取消，未做任何修改"
    }

    func toggle(_ v: EnvironmentVariable) {
        requestChange("\(v.enabled ? "启用" : "禁用") \(v.name)") {
            [try self.edit.planToggle(v, enable: !v.enabled)]
        }
    }

    func update(_ v: EnvironmentVariable, value: String) {
        requestChange("编辑 \(v.name)") {
            [try self.edit.planUpdateValue(v, newValue: value)]
        }
    }

    func remove(_ v: EnvironmentVariable) {
        requestChange("删除 \(v.name)") {
            [try self.edit.planRemove(v)]
        }
    }

    func add(name: String, value: String, user: Bool) {
        requestChange("新增 \(name)") {
            [try self.edit.planAdd(name: name, value: value, user: user)]
        }
    }

    func dedupe(_ group: DuplicateGroup, disable: Bool) {
        requestChange("\(disable ? "禁用" : "删除")多余定义 \(group.name)") {
            try self.edit.planDedupe(group: group, disable: disable)
        }
    }

    /// 提交新的受管 PATH 列表（增删/排序，F04-03），经预览确认落盘。
    func requestManagedPath(_ entries: [String]) {
        requestChange("更新受管 PATH 条目") {
            [try self.managedPath.plan(entries)]
        }
    }

    /// 新增/修改一个受管 GUI（launchd）环境变量（F10-01），确认后同步 setenv。
    func requestGuiEnvSet(name: String, value: String) {
        requestChange("设置 GUI 变量 \(name)",
                      after: { [weak self] in self?.launchEnv.applySet(name: name, value: value) }) {
            [try self.launchEnv.planSet(name: name, value: value)]
        }
    }

    /// 移除一个受管 GUI 环境变量，确认后 unsetenv。
    func requestGuiEnvRemove(name: String) {
        requestChange("移除 GUI 变量 \(name)",
                      after: { [weak self] in self?.launchEnv.applyUnset(name: name) }) {
            [try self.launchEnv.planRemove(name: name)]
        }
    }

    /// 运行 GUI vs Shell 环境差异诊断（F10-02），并刷新审计日志面板；
    /// 完成后在主线程回调结果，供视图弹出差异详情窗口。
    func runDiagnostics(completion: (([EnvDiffRow]) -> Void)? = nil) {
        isBusy = true
        statusMessage = "正在对比登录 Shell 与 GUI 环境…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let rows = DiagnosticsService.compare()
            let audit = WriteAudit.recent(50)
            DispatchQueue.main.async {
                self.envDiffRows = rows
                self.auditLog = audit
                self.isBusy = false
                self.statusMessage = rows.isEmpty
                    ? "诊断完成：GUI 与 Shell 环境无异常差异"
                    : "诊断完成：发现 \(rows.count) 项差异"
                completion?(rows)
            }
        }
    }

    // MARK: - 批次③：项目环境 / venv / Profile（F10-03 / F06-09 / F10-04）

    /// 扫描项目目录的环境文件（F10-03，只读）。
    func scanProject(dir: String) {
        let d = (dir as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: d) else {
            statusMessage = "⚠️ 目录不存在：\(d)"
            return
        }
        projectDir = d
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let files = ProjectEnvScanner.scan(projectDir: d)
            DispatchQueue.main.async {
                self.projectEnvFiles = files
                self.isBusy = false
                self.statusMessage = files.isEmpty
                    ? "项目未发现环境文件"
                    : "项目发现 \(files.count) 个环境文件"
            }
        }
    }

    /// 浅扫描发现已有 venv（F06-09）。
    func discoverVenvs() {
        isBusy = true
        statusMessage = "正在搜索项目 venv…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let found = VenvService.discover()
            DispatchQueue.main.async {
                self.venvs = found
                self.isBusy = false
                self.statusMessage = "发现 \(found.count) 个虚拟环境"
            }
        }
    }

    /// 创建 venv，输出流式写入 installLog。
    func createVenv(pythonExe: String, path: String) {
        installLog = ""
        isInstalling = true
        VenvService.create(pythonExe: pythonExe, path: path,
                           onLine: { [weak self] line in self?.installLog += line + "\n" },
                           onDone: { [weak self] code in
            guard let self = self else { return }
            self.isInstalling = false
            self.installLog += code == 0 ? "\n✅ 创建完成" : "\n❌ 创建失败（退出码 \(code)）"
            self.statusMessage = code == 0 ? "venv 已创建：\(path)" : "venv 创建失败"
            self.discoverVenvs()
        })
    }

    /// 删除 venv（仅限含 pyvenv.cfg 的目录）。
    func deleteVenv(_ info: VenvService.Info) {
        do {
            try VenvService.delete(path: info.path)
            statusMessage = "✅ 已删除 venv：\(info.path)"
            venvs.removeAll { $0.id == info.id }
        } catch let e as EditError {
            statusMessage = "⚠️ " + e.message
        } catch {
            statusMessage = "⚠️ " + error.localizedDescription
        }
    }

    /// 保存当前用户级变量为 Profile 方案（F10-04）。
    func saveProfile(name: String, includeSecrets: Bool) {
        do {
            let p = try profileSvc.save(name: name, from: entries, includeSecrets: includeSecrets)
            statusMessage = "✅ 方案已保存：\(p.name)（\(p.vars.count) 个变量）"
            profiles = profileSvc.list()
        } catch let e as EditError {
            statusMessage = "⚠️ " + e.message
        } catch {
            statusMessage = "⚠️ " + error.localizedDescription
        }
    }

    func deleteProfile(_ p: EnvProfile) {
        profileSvc.delete(name: p.name)
        profiles.removeAll { $0.id == p.id }
        statusMessage = "已删除方案：\(p.name)"
    }

    /// 应用方案（被勾选的变量写入 ~/.zshrc Profile 受管区块），经 diff 预览确认。
    func applyProfile(_ p: EnvProfile, included: Set<String>) {
        requestChange("应用方案 \(p.name)") {
            [try self.profileSvc.planApply(profile: p, included: included)]
        }
    }

    /// 对比两个方案（F10-04）。
    func compareProfiles(_ a: EnvProfile, _ b: EnvProfile) -> [ProfileDiffRow] {
        ProfileService.diff(a, b)
    }

    /// 忽略某组重复提醒（F05），同类不再提示；可在设置页恢复。
    func ignoreDuplicate(_ group: DuplicateGroup) {
        ignoredDupNames.insert(group.name + "#" + group.category.rawValue)
        statusMessage = "已忽略「\(group.name)」的此类提醒，可在设置与诊断页恢复"
        refresh()
    }

    func restoreIgnoredDuplicates() {
        ignoredDupNames = []
        statusMessage = "已恢复全部重复提醒"
        refresh()
    }

    func activateRuntime(_ install: RuntimeInstall) {
        perform("激活 \(install.language.label) \(install.version)") {
            try self.runtime.activate(install)
        }
    }

    func uninstallRuntime(_ install: RuntimeInstall) {
        perform("卸载 \(install.language.label) \(install.version)") {
            try self.runtime.uninstall(install)
        }
    }

    /// 启动一次版本安装：输出流式写入 installLog，完成后自动刷新。
    func startInstall(manager: InstallManager, version: String) {
        installLog = ""
        isInstalling = true
        RuntimeInstallService.install(manager: manager, version: version,
                                      onLine: { [weak self] line in
            self?.installLog += line + "\n"
        }, onDone: { [weak self] code in
            guard let self = self else { return }
            self.isInstalling = false
            self.installLog += code == 0 ? "\n✅ 安装完成" : "\n❌ 安装失败（退出码 \(code)）"
            self.statusMessage = code == 0 ? "安装完成：\(manager.label) \(version)" : "安装失败"
            self.refresh()
        })
    }

    func undoChange() {
        perform("撤销") { try self.undo.undo() }
    }

    func redoChange() {
        perform("重做") { try self.undo.redo() }
    }

    // MARK: - 私有：统一执行 + 错误处理 + 刷新（供撤销/运行时类一步式操作复用）

    private func perform(_ label: String, _ body: () throws -> Void) {
        do {
            try body()
            lastOutcome = .savedNewShell(label)
            statusMessage = "✅ \(label) 完成 — 新开终端后生效"
            refresh()
        } catch let e as EditError {
            lastOutcome = .failed(e.message)
            statusMessage = "⚠️ " + e.message
        } catch {
            lastOutcome = .failed(error.localizedDescription)
            statusMessage = "⚠️ " + error.localizedDescription
        }
    }
}
