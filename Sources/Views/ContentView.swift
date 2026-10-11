import SwiftUI

/// 根视图：左侧纵向导航 + 右侧内容页 + 底部状态栏。
struct ContentView: View {
    @EnvironmentObject var vm: EnvManagerViewModel

    enum Page: Hashable { case env, path, dup, runtime, project, settings

        /// 供 --screenshot --page <name> 调试模式解析初始页。
        init?(name: String) {
            switch name {
            case "env": self = .env
            case "path": self = .path
            case "dup": self = .dup
            case "runtime": self = .runtime
            case "project": self = .project
            case "settings": self = .settings
            default: return nil
            }
        }
    }
    @State private var page: Page = ScreenshotMode.pageName.flatMap(Page.init(name:)) ?? .env
    @State private var showWelcome = WelcomeState.needsWelcome && !ScreenshotMode.isActive

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                sidebar
                Divider()
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            statusBar
        }
        .frame(minWidth: 920, minHeight: 560)
        .background(Theme.windowBG)
        .onAppear {
            if vm.entries.isEmpty { vm.refresh() }
            // F10-01：启动后重放受管 GUI 变量（系统重启后 launchd 会丢失）
            DispatchQueue.global(qos: .utility).async { vm.launchEnv.replayOnStartup() }
            // 隐藏截图模式：等渲染完成后抓窗写 PNG 并退出
            if ScreenshotMode.isActive { ScreenshotMode.capture() }
        }
        // 首次启动引导（F09）
        .sheet(isPresented: $showWelcome) {
            WelcomeSheet(
                onDismiss: { WelcomeState.finish(); showWelcome = false },
                onOpenSettings: { WelcomeState.finish(); showWelcome = false; page = .settings })
        }
        // 菜单栏请求跳转设置页
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsPage)) { _ in
            page = .settings
        }
        // 写操作前的 diff 变更预览（F02-07）
        .sheet(item: $vm.pendingChange) { pc in
            ChangePreviewSheet(label: pc.label, plans: pc.plans,
                               onConfirm: { vm.confirmPendingChange() },
                               onCancel: { vm.cancelPendingChange() })
        }
    }

    // MARK: - 左侧纵向导航

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("EnvManage")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(Theme.primaryText)
                .padding(.horizontal, 12)
                .padding(.top, 16)
                .padding(.bottom, 10)

            navItem(.env, title: "环境变量", icon: "list.bullet.rectangle.fill")
            navItem(.path, title: "PATH 管理", icon: "folder.badge.gearshape")
            navItem(.dup, title: "重复检测", icon: "doc.on.doc.fill",
                    badge: vm.duplicates.isEmpty ? nil : vm.duplicates.count)
            navItem(.runtime, title: "运行时管理", icon: "chevron.left.forwardslash.chevron.right",
                    subtitle: "Python / Java / Node / Go / C++")
            navItem(.project, title: "项目环境", icon: "laptop.circle.fill",
                    subtitle: ".env / venv / 工具链")
            navItem(.settings, title: "设置与诊断", icon: "gearshape.2.fill",
                    subtitle: "GUI 变量 / 审计 / 安全")

            Spacer()
        }
        .frame(minWidth: 170, idealWidth: 190, maxWidth: 210, alignment: .leading)
        .frame(maxHeight: .infinity)
        .background(Theme.subtleBG)
    }

    private func navItem(_ target: Page, title: String, icon: String,
                         badge: Int? = nil, subtitle: String? = nil) -> some View {
        Button(action: { page = target }) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundColor(page == target ? Theme.accent : Theme.secondaryText)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13, weight: page == target ? .semibold : .regular))
                        .foregroundColor(page == target ? Theme.primaryText : Theme.secondaryText)
                        .lineLimit(1).truncationMode(.tail)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 9))
                            .foregroundColor(Theme.secondaryText.opacity(0.7))
                            .lineLimit(1).truncationMode(.tail)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 4)
                if let badge {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(height: Theme.badgeH)               // 统一标签高度
                        .padding(.horizontal, 6)
                        .background(Theme.danger)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(page == target ? Theme.accent.opacity(0.10) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .cornerRadius(8)
        .padding(.horizontal, 8)
    }

    // MARK: - 右侧内容

    @ViewBuilder
    private var detail: some View {
        switch page {
        case .env:     EnvironmentVariablesView()
        case .path:    PathEntriesView()
        case .dup:     DuplicatesView()
        case .runtime: RuntimeManagerView()
        case .project: ProjectEnvView()
        case .settings: SettingsView()
        }
    }

    // MARK: - 底部状态栏

    private var statusBar: some View {
        HStack(spacing: 12) {
            if vm.isBusy {
                ProgressView().controlSize(.small)
            }
            Text(vm.statusMessage)
                .font(.caption)
                .foregroundColor(Theme.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 80, alignment: .leading)

            Spacer(minLength: 8)

            scopeSummary
                .fixedSize()
                .layoutPriority(1)

            Divider().frame(height: 14)

            HStack(spacing: 8) {
                Button(action: { vm.undoChange() }) { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(EnvButtonStyle(kind: .icon(Theme.primaryText)))
                    .help("撤销 (⌘Z)").disabled(!vm.undo.canUndo)
                Button(action: { vm.redoChange() }) { Image(systemName: "arrow.uturn.forward") }
                    .buttonStyle(EnvButtonStyle(kind: .icon(Theme.primaryText)))
                    .help("重做 (⇧⌘Z)").disabled(!vm.undo.canRedo)
            }
            .fixedSize()
            .layoutPriority(2)
        }
        .padding(.horizontal, Theme.hpad)
        .padding(.vertical, 7)
        .background(Theme.subtleBG)
        .overlay(Divider(), alignment: .top)
    }

    private var scopeSummary: some View {
        HStack(spacing: 10) {
            countItem(.user)
            countItem(.system)
            countItem(.runtime)
        }
        .font(.caption)
    }

    private func countItem(_ scope: EnvScope) -> some View {
        HStack(spacing: 3) {
            Circle().fill(scope.color).frame(width: 8, height: 8)
            Text(scope.label).foregroundColor(Theme.secondaryText)
            Text("\(vm.counts[scope] ?? 0)").foregroundColor(Theme.primaryText)
        }
    }
}
