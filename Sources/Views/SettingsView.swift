import SwiftUI
import AppKit

/// 「设置与诊断」页（F09 / F10-01 / F10-02 / F10-09）：
/// 显示选项、受管 GUI（launchd）环境变量、GUI vs Shell 差异诊断、
/// 已忽略重复提醒、写操作审计日志与安全机制说明。
struct SettingsView: View {
    @EnvironmentObject var vm: EnvManagerViewModel
    @State private var newGUIName = ""
    @State private var newGUIValue = ""
    // Profile 方案（F10-04）
    @State private var profileName = ""
    @State private var profileIncludeSecrets = false
    @State private var applyingProfile: EnvProfile? = nil
    @State private var profileIncluded: Set<String> = []
    @State private var compareA = ""
    @State private var compareB = ""
    // 差异诊断结果弹窗（长值行内截断看不清，改弹窗完整展示）
    @State private var showDiffSheet = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                displaySection
                profileSection
                guiEnvSection
                diagnosticsSection
                ignoredSection
                auditSection
                safetySection
            }
            .padding(16)
        }
        .background(Theme.windowBG)
    }

    // MARK: - 显示与启动选项（F09）

    private var displaySection: some View {
        sectionCard(title: "显示与启动", icon: "slider.horizontal.3") {
            Toggle("敏感变量明文展示", isOn: $vm.revealSecrets)
                .toggleStyle(.switch).controlSize(.small)
            Toggle("主列表按名称聚合", isOn: $vm.groupByName)
                .toggleStyle(.switch).controlSize(.small)
            HStack(spacing: 10) {
                Button(action: { vm.launchEnv.replayOnStartup(); vm.refresh() }) {
                    Label("重放 GUI 变量", systemImage: "arrow.clockwise.circle")
                }
                .buttonStyle(EnvButtonStyle(kind: .bordered))
                .help("把受管 GUI（launchd）变量清单重新应用到当前会话（系统重启后需要）")
                Button(action: { WelcomeState.reset() }) {
                    Label("重置首次引导", systemImage: "questionmark.circle")
                }
                .buttonStyle(EnvButtonStyle(kind: .bordered))
                .help("下次启动时重新显示欢迎与引导页")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Profile 方案（F10-04）

    private var profileSection: some View {
        sectionCard(title: "环境 Profile 方案", icon: "square.stack.3d.up") {
            Text("把当前用户级变量保存为命名快照；应用时逐项勾选，写入 ~/.zshrc 的 Profile 受管区块（经 diff 预览确认）。敏感变量默认不纳入。")
                .font(.caption).foregroundColor(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                TextField("方案名，如 work / personal", text: $profileName)
                    .textFieldStyle(.plain).frame(width: 170).uniformInput()
                Button("保存当前环境") { vm.saveProfile(name: profileName, includeSecrets: profileIncludeSecrets); profileName = "" }
                    .buttonStyle(EnvButtonStyle(kind: .primary)).fixedSize()
                    .disabled(profileName.trimmingCharacters(in: .whitespaces).isEmpty)
                Toggle("含敏感", isOn: $profileIncludeSecrets)
                    .toggleStyle(.switch).controlSize(.small)
                    .font(.caption)
            }

            if vm.profiles.isEmpty {
                Text("尚无方案。")
                    .font(.caption).foregroundColor(Theme.secondaryText)
            } else {
                ForEach(vm.profiles) { p in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(p.name)
                                .font(.system(.callout, design: .monospaced).weight(.semibold))
                                .foregroundColor(Theme.primaryText)
                                .lineLimit(1).truncationMode(.tail)
                            Text("\(p.vars.count) 个变量 · \(p.createdAt)")
                                .font(.caption2).foregroundColor(Theme.secondaryText).fixedSize()
                            Spacer(minLength: 4)
                            Button(action: { startApply(p) }) {
                                Label(applyingProfile?.id == p.id ? "收起" : "应用",
                                      systemImage: "square.and.arrow.down")
                            }
                            .buttonStyle(EnvButtonStyle(kind: .bordered)).fixedSize()
                            Button(action: { vm.deleteProfile(p) }) {
                                Image(systemName: "trash").font(.system(size: 11))
                            }
                            .buttonStyle(EnvButtonStyle(kind: .icon(Theme.danger), hpad: 8))
                            .fixedSize()
                        }
                        if applyingProfile?.id == p.id {
                            ForEach(p.vars.keys.sorted(), id: \.self) { key in
                                Toggle(isOn: bindingFor(key)) {
                                    HStack(spacing: 6) {
                                        Text(key)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(Theme.primaryText)
                                            .lineLimit(1).truncationMode(.tail)
                                        Text(p.vars[key] ?? "")
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundColor(Theme.secondaryText)
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                }
                                .toggleStyle(.switch).controlSize(.mini)
                            }
                            Button(action: {
                                if let p = applyingProfile { vm.applyProfile(p, included: profileIncluded) }
                            }) {
                                Label("应用勾选的 \(profileIncluded.count) 项", systemImage: "doc.badge.gearshape.fill")
                            }
                            .buttonStyle(EnvButtonStyle(kind: .primary)).fixedSize()
                            .disabled(profileIncluded.isEmpty)
                        }
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.subtleBG)
                    .cornerRadius(7)
                }

                // 对比两个方案
                if vm.profiles.count >= 2 {
                    Divider()
                    HStack(spacing: 8) {
                        Picker("", selection: $compareA) {
                            ForEach(vm.profiles) { Text($0.name).tag($0.name) }
                        }.labelsHidden().frame(maxWidth: 130)
                        Image(systemName: "arrow.left.arrow.right").foregroundColor(Theme.secondaryText)
                        Picker("", selection: $compareB) {
                            ForEach(vm.profiles) { Text($0.name).tag($0.name) }
                        }.labelsHidden().frame(maxWidth: 130)
                        Text("对比").font(.caption).foregroundColor(Theme.secondaryText).fixedSize()
                    }
                    let rows = diffRows()
                    if rows.isEmpty {
                        Text("两个方案变量与值完全一致（或选了同一方案）。")
                            .font(.caption2).foregroundColor(Theme.secondaryText)
                    } else {
                        ForEach(rows.prefix(20)) { r in
                            HStack(spacing: 6) {
                                Text(r.kind.rawValue)
                                    .font(.caption2)
                                    .foregroundColor(r.kind == .changed ? Theme.danger : (r.kind == .added ? Theme.success : Theme.warning))
                                    .frame(width: 52, alignment: .leading)
                                Text(r.name)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(Theme.primaryText)
                                    .lineLimit(1).truncationMode(.tail)
                                Spacer(minLength: 4)
                                Text("A: \(r.leftValue ?? "—") · B: \(r.rightValue ?? "—")")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(Theme.secondaryText)
                                    .lineLimit(1).truncationMode(.middle)
                                    .frame(maxWidth: 260, alignment: .trailing)
                            }
                        }
                        if rows.count > 20 {
                            Text("仅显示前 20 项，共 \(rows.count) 项差异。")
                                .font(.caption2).foregroundColor(Theme.secondaryText)
                        }
                    }
                }
            }
        }
    }

    private func startApply(_ p: EnvProfile) {
        if applyingProfile?.id == p.id {
            applyingProfile = nil
        } else {
            applyingProfile = p
            profileIncluded = Set(p.vars.keys)   // 默认全选
        }
    }

    private func bindingFor(_ key: String) -> Binding<Bool> {
        Binding(get: { profileIncluded.contains(key) },
                set: { on in if on { profileIncluded.insert(key) } else { profileIncluded.remove(key) } })
    }

    private func diffRows() -> [ProfileDiffRow] {
        guard let a = vm.profiles.first(where: { $0.name == compareA }),
              let b = vm.profiles.first(where: { $0.name == compareB }),
              a.id != b.id
        else { return [] }
        return vm.compareProfiles(a, b)
    }

    // MARK: - 受管 GUI 环境变量（F10-01）

    private var guiEnvSection: some View {
        sectionCard(title: "GUI 环境变量（launchd）", icon: "app.badge.gearshape") {
            Text("双击启动的 App 不读取 shell 配置，其环境来自 launchd 会话。此清单会在确认后通过 launchctl setenv 立即应用，并在 EnvManage 启动时自动重放。")
                .font(.caption).foregroundColor(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            if vm.guiEnvEntries.isEmpty {
                Text("暂无受管 GUI 变量。")
                    .font(.caption).foregroundColor(Theme.secondaryText)
            } else {
                ForEach(vm.guiEnvEntries) { e in
                    HStack(spacing: 8) {
                        Text(e.name)
                            .font(.system(.callout, design: .monospaced).weight(.semibold))
                            .foregroundColor(Theme.primaryText)
                            .lineLimit(1).truncationMode(.middle)
                        Text("=").foregroundColor(Theme.secondaryText)
                        Text(e.value)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundColor(Theme.primaryText)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(e.inSync ? "已应用" : "未同步")
                            .font(.caption2).foregroundColor(e.inSync ? Theme.success : Theme.warning)
                            .uniformTag()
                            .background((e.inSync ? Theme.success : Theme.warning).opacity(0.12))
                            .cornerRadius(5)
                            .fixedSize()
                        Button(action: { vm.requestGuiEnvRemove(name: e.name) }) {
                            Image(systemName: "xmark").font(.system(size: 11))
                        }
                        .buttonStyle(EnvButtonStyle(kind: .icon(Theme.danger), hpad: 8))
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack(spacing: 8) {
                TextField("变量名，如 JAVA_HOME", text: $newGUIName)
                    .textFieldStyle(.plain).frame(width: 150).uniformInput()
                TextField("变量值", text: $newGUIValue)
                    .textFieldStyle(.plain).uniformInput()
                    .onSubmit(addGUI)
                Button(action: addGUI) { Label("添加/更新", systemImage: "plus") }
                    .buttonStyle(EnvButtonStyle(kind: .primary)).fixedSize()
                    .disabled(newGUIName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func addGUI() {
        let n = newGUIName.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        vm.requestGuiEnvSet(name: n, value: newGUIValue)
        newGUIName = ""; newGUIValue = ""
    }

    // MARK: - GUI vs Shell 差异诊断（F10-02）

    private var diagnosticsSection: some View {
        sectionCard(title: "GUI 与 Shell 环境差异诊断", icon: "stethoscope") {
            HStack(spacing: 10) {
                Button(action: { vm.runDiagnostics { _ in showDiffSheet = true } }) {
                    Label("开始对比", systemImage: "play.circle")
                }
                .buttonStyle(EnvButtonStyle(kind: .primary)).fixedSize()
                .disabled(vm.isBusy)
                Text("运行 zsh -lc env 与当前 GUI 进程环境逐变量比对（忽略终端噪音变量），结果在弹窗中完整展示。")
                    .font(.caption).foregroundColor(Theme.secondaryText)
                    .lineLimit(2)
                Spacer()
            }
            if vm.envDiffRows.isEmpty {
                Text("尚未运行诊断，或未发现异常差异。")
                    .font(.caption).foregroundColor(Theme.secondaryText)
            } else {
                // 行内只给各类别计数摘要，详情走弹窗（长值不截断、可搜索/复制）
                HStack(spacing: 8) {
                    ForEach([EnvDiffRow.Kind.onlyInShell, .onlyInGUI, .valueDiff], id: \.self) { k in
                        let n = vm.envDiffRows.filter { $0.kind == k }.count
                        if n > 0 {
                            Text("\(k.rawValue) ×\(n)")
                                .font(.caption2).foregroundColor(kindColor(k))
                                .uniformTag()
                                .background(kindColor(k).opacity(0.12))
                                .cornerRadius(5)
                                .fixedSize()
                        }
                    }
                    Spacer()
                    Button(action: { showDiffSheet = true }) {
                        Label("查看差异详情", systemImage: "arrow.right.square")
                    }
                    .buttonStyle(EnvButtonStyle(kind: .bordered)).fixedSize()
                }
            }
        }
        .sheet(isPresented: $showDiffSheet) {
            EnvDiffSheet(rows: vm.envDiffRows, onDismiss: { showDiffSheet = false })
        }
    }

    private func kindColor(_ k: EnvDiffRow.Kind) -> Color {
        switch k {
        case .onlyInShell: return Theme.warning
        case .onlyInGUI:   return Theme.accent
        case .valueDiff:   return Theme.danger
        }
    }

    // MARK: - 已忽略的重复提醒（F05）

    private var ignoredSection: some View {
        sectionCard(title: "重复检测提醒", icon: "bell.slash") {
            HStack(spacing: 10) {
                Text(vm.ignoredDupNames.isEmpty
                     ? "当前没有已忽略的重复提醒。"
                     : "已忽略 \(vm.ignoredDupNames.count) 类重复提醒（同类不再显示）。")
                    .font(.caption).foregroundColor(Theme.secondaryText)
                Spacer()
                if !vm.ignoredDupNames.isEmpty {
                    Button(action: { vm.restoreIgnoredDuplicates() }) {
                        Label("全部恢复", systemImage: "bell.badge")
                    }
                    .buttonStyle(EnvButtonStyle(kind: .bordered)).fixedSize()
                }
            }
        }
    }

    // MARK: - 审计日志（F10-09）

    private var auditSection: some View {
        sectionCard(title: "写操作审计日志", icon: "doc.text.magnifyingglass") {
            Button(action: { vm.auditLog = WriteAudit.recent(50) }) {
                Label("读取最近记录", systemImage: "arrow.clockwise")
            }
            .buttonStyle(EnvButtonStyle(kind: .bordered)).fixedSize()

            if vm.auditLog.isEmpty {
                Text("暂无审计记录（每次成功/失败的落盘操作都会记入本地 jsonl）。")
                    .font(.caption).foregroundColor(Theme.secondaryText)
            } else {
                ForEach(Array(vm.auditLog.prefix(30).enumerated()), id: \.offset) { _, e in
                    HStack(spacing: 8) {
                        Text(e["time"] ?? "").font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.secondaryText).fixedSize()
                        Text((e["action"] ?? "") + " → " + (e["file"] ?? ""))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Theme.primaryText)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text((e["privileged"] == "1") ? "提权" : "")
                            .font(.caption2).foregroundColor(Theme.warning).fixedSize()
                        Text(e["result"] ?? "")
                            .font(.caption2)
                            .foregroundColor((e["result"] ?? "").hasPrefix("失败") ? Theme.danger : Theme.success)
                            .lineLimit(1).truncationMode(.tail).fixedSize()
                    }
                    .padding(.vertical, 1)
                }
            }
            Button(action: {
                NSWorkspace.shared.activateFileViewerSelecting([WriteAudit.logURL])
            }) {
                Label("在访达中显示日志文件", systemImage: "folder")
            }
            .buttonStyle(EnvButtonStyle(kind: .bordered)).fixedSize()
        }
    }

    // MARK: - 安全机制说明（F08 / F10-09）

    private var safetySection: some View {
        sectionCard(title: "安全机制", icon: "lock.shield") {
            bullet("每次写入前：基线哈希校验（拒绝覆盖外部修改）+ zsh -n 语法预检 + 自动备份")
            bullet("系统文件仅允许白名单：/etc/zshenv、/etc/zprofile、/etc/zshrc、/etc/profile；/etc/paths* 一律只读")
            bullet("所有写操作弹出 diff 预览确认；⌘Z 可整体撤销，备份存于 Application Support/EnvManage/Backups")
            HStack(spacing: 10) {
                Button(action: {
                    NSWorkspace.shared.activateFileViewerSelecting([AppInfo.backupDir])
                }) {
                    Label("打开备份目录", systemImage: "folder.fill")
                }
                .buttonStyle(EnvButtonStyle(kind: .bordered)).fixedSize()
            }
        }
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark.circle").font(.system(size: 10))
                .foregroundColor(Theme.success).padding(.top, 3)
            Text(s).font(.caption).foregroundColor(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 通用卡片

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, icon: String,
                                            @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline).foregroundColor(Theme.primaryText)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBG)
        .cornerRadius(Theme.corner)
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.separator, lineWidth: 1))
    }
}

// MARK: - 首次启动引导（F09）

/// 首次启动欢迎与工作原理说明。
enum WelcomeState {
    static let key = "EnvManage.onboarded"
    static var needsWelcome: Bool { !UserDefaults.standard.bool(forKey: key) }
    static func finish() { UserDefaults.standard.set(true, forKey: key) }
    static func reset() { UserDefaults.standard.set(false, forKey: key) }
}

struct WelcomeSheet: View {
    let onDismiss: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("欢迎使用 EnvManage", systemImage: "gearshape.2.fill")
                .font(.title2.weight(.bold)).foregroundColor(Theme.primaryText)
            Text("这里集中管理 macOS 的 shell 环境变量。开始之前，请花 20 秒了解它的工作方式：")
                .font(.callout).foregroundColor(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                point("01", "扫描读取 /etc 与 ~/.zshrc 等配置，只展示，绝不擅自写入。")
                point("02", "任何修改都会先给出文件级 diff 预览，确认后才落盘。")
                point("03", "落盘前自动校验文件是否被外部修改，并做 zsh 语法预检与备份。")
                point("04", "系统文件仅在白名单内支持提权写入；/etc/paths 保持只读。")
            }
            HStack(spacing: 10) {
                Button("进入设置与诊断页") { onOpenSettings() }
                    .buttonStyle(EnvButtonStyle(kind: .bordered))
                Spacer()
                Button("开始使用") { onDismiss() }
                    .buttonStyle(EnvButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 480)
        .background(Theme.windowBG)
    }

    private func point(_ no: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(no)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(Theme.accent)
                .frame(width: 26, height: Theme.badgeH)
                .background(Theme.accent.opacity(0.12))
                .cornerRadius(5)
            Text(text).font(.callout).foregroundColor(Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - 菜单栏内容（F10-06）

extension Notification.Name {
    /// 从菜单栏请求跳转到「设置与诊断」页。
    static let openSettingsPage = Notification.Name("EnvManage.openSettings")
}

/// MenuBarExtra 下拉内容：快捷刷新、窗口跳转、最近审计。
struct MenuBarContent: View {
    @ObservedObject var vm: EnvManagerViewModel

    var body: some View {
        Text("EnvManage · \(vm.entries.count) 条记录")
        if !vm.duplicates.isEmpty {
            Text("待处理重复：\(vm.duplicates.count) 组").foregroundColor(.orange)
        }
        Divider()
        Button("刷新环境") { vm.refresh() }
        Button("显示主窗口") {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            for w in NSApp.windows where w.canBecomeMain { w.makeKeyAndOrderFront(nil); break }
        }
        Button("打开设置与诊断") {
            NotificationCenter.default.post(name: .openSettingsPage, object: nil)
            ButtonAction.activateMainWindow()
        }
        Divider()
        if let recent = WriteAudit.recent(3).first {
            Text("最近操作：\(recent["action"] ?? "") @ \(recent["time"] ?? "")")
                .font(.caption2)
        }
        Divider()
        Button("退出") { NSApp.terminate(nil) }
    }
}

enum ButtonAction {
    static func activateMainWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for w in NSApp.windows where w.canBecomeMain { w.makeKeyAndOrderFront(nil); break }
    }
}
