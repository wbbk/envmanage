import SwiftUI

/// 安装版本弹窗：选择语言 -> 安装渠道（单选）-> 版本号下拉可输入筛选，
/// 实时流式展示安装日志。
struct InstallRuntimeSheet: View {
    @EnvironmentObject var vm: EnvManagerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var language: RuntimeLanguage = .python
    @State private var managerLabel: String = ""
    @State private var version: String = ""

    // 版本候选（下拉数据源）
    @State private var versionOptions: [String] = []
    @State private var isLoadingVersions = false

    private var managers: [InstallManager] { RuntimeInstallService.managers(for: language) }

    private var selectedManager: InstallManager? {
        managers.first { $0.label == managerLabel }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("安装语言运行时版本")
                .font(.title2.weight(.semibold))

            // 语言选择（统一分段控件，与按钮/输入框等高）
            VStack(alignment: .leading, spacing: 6) {
                Text("语言").font(.caption).foregroundColor(Theme.secondaryText)
                SegmentedToggle(options: RuntimeLanguage.allCases.map { ($0.label, $0) },
                                selection: $language)
            }

            // 安装渠道：单选（radio 样式，仅选中项填充圆点）
            VStack(alignment: .leading, spacing: 4) {
                Text("安装渠道").font(.caption).foregroundColor(Theme.secondaryText)
                ForEach(managers) { m in
                    radioRow(m)
                }
            }

            // 版本号：下拉选择 + 手动输入筛选；开始安装按钮与输入框同行等高对齐
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("版本号").font(.caption).foregroundColor(Theme.secondaryText)
                    if isLoadingVersions {
                        ProgressView().controlSize(.small)
                        Text("正在获取可安装版本…")
                            .font(.caption2).foregroundColor(Theme.secondaryText)
                    } else if !versionOptions.isEmpty {
                        Text("共 \(versionOptions.count) 个可选版本，可直接输入筛选")
                            .font(.caption2).foregroundColor(Theme.secondaryText)
                    }
                    Spacer()
                }
                HStack(spacing: 10) {
                    VersionComboBox(text: $version,
                                    options: versionOptions,
                                    placeholder: "选择或输入版本号，如 3.12.1",
                                    isEnabled: !vm.isInstalling)
                        .frame(height: Theme.controlH)
                    Button(vm.isInstalling ? "安装中…" : "开始安装") { start() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(EnvButtonStyle(kind: .primary))
                        .fixedSize()
                        .disabled(vm.isInstalling || version.isEmpty || selectedManager == nil)
                }
            }

            // 日志
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("输出日志").font(.caption).foregroundColor(Theme.secondaryText)
                    if vm.isInstalling { ProgressView().controlSize(.small) }
                    Spacer()
                }
                ScrollView {
                    Text(vm.installLog.isEmpty ? "（等待开始…）" : vm.installLog)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(Theme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(height: 180)
                .background(Theme.subtleBG)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.separator, lineWidth: 1))
            }

            HStack {
                Spacer()
                Button(vm.isInstalling ? "后台运行" : "关闭") { dismiss() }
                    .buttonStyle(EnvButtonStyle(kind: .bordered))
            }
        }
        .padding(20)
        .frame(width: 560)
        .background(Theme.windowBG)
        .onAppear {
            if managerLabel.isEmpty {
                managerLabel = managers.first(where: { $0.available })?.label ?? ""
            }
            loadVersions()
        }
        .onChange(of: language) { _ in
            managerLabel = managers.first(where: { $0.available })?.label ?? ""
            loadVersions()
        }
        .onChange(of: managerLabel) { _ in loadVersions() }
    }

    // MARK: - 渠道单选行

    private func radioRow(_ m: InstallManager) -> some View {
        let selected = m.label == managerLabel
        return Button(action: { if m.available { managerLabel = m.label } }) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundColor(selected ? Theme.accent :
                        (m.available ? Theme.secondaryText : Theme.secondaryText.opacity(0.4)))
                Text(m.label)
                    .foregroundColor(m.available ? Theme.primaryText : Theme.secondaryText.opacity(0.5))
                if !m.available {
                    Text("（本机未安装）")
                        .font(.caption).foregroundColor(Theme.secondaryText.opacity(0.6))
                }
                Spacer()
                Text(m.hint)
                    .font(.caption2).foregroundColor(Theme.secondaryText.opacity(0.7))
                    .lineLimit(1)
            }
            .padding(.vertical, 4).padding(.horizontal, 6)
            .background(selected ? Theme.accent.opacity(0.08) : Color.clear)
            .cornerRadius(6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!m.available)
    }

    // MARK: - 版本候选拉取

    private func loadVersions() {
        versionOptions = []
        guard let m = selectedManager, m.listCommand != nil else { return }
        isLoadingVersions = true
        RuntimeInstallService.fetchVersions(manager: m) { list in
            // @State 共享存储箱：回调里读到的是当前值，渠道已切换则丢弃过期结果
            guard managerLabel == m.label else {
                isLoadingVersions = false
                return
            }
            versionOptions = list
            isLoadingVersions = false
        }
    }

    private func start() {
        guard let m = selectedManager else { return }
        vm.startInstall(manager: m, version: version)
    }
}
