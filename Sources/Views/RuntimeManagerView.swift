import SwiftUI
import AppKit

/// 「运行时管理」视图：统一管理 Python / Java / Node.js / Go / C++ 多版本，
/// 支持激活（设为默认）、卸载、安装指定版本，并展示各版本下的虚拟环境。
struct RuntimeManagerView: View {
    @EnvironmentObject var vm: EnvManagerViewModel
    @State private var showInstall = false

    var body: some View {
        VStack(spacing: 0) {
            header
            languageBar
            Divider()
            list
            footer
        }
        .background(Theme.windowBG)
        .sheet(isPresented: $showInstall) {
            InstallRuntimeSheet()
        }
    }

    // MARK: - 头部与语言筛选

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("语言运行时管理").font(.headline)
                Text("共检测到 \(vm.runtimes.count) 个安装 · \(vm.runtimes.filter { $0.active }.count) 个已激活")
                    .font(.caption).foregroundColor(Theme.secondaryText)
                    .lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            Button(action: { vm.refresh() }) {
                Label("重新检测", systemImage: "arrow.clockwise")
            }
            .buttonStyle(EnvButtonStyle(kind: .bordered))
            .fixedSize()
            Button(action: { showInstall = true }) {
                Label("安装版本", systemImage: "plus.circle.fill")
            }
            .buttonStyle(EnvButtonStyle(kind: .primary))
            .fixedSize()
        }
        .padding(.horizontal, Theme.hpad)
        .padding(.vertical, 12)
    }

    private var languageBar: some View {
        // 窄窗口下可横向滚动，不撑爆整体布局
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(title: "全部", on: vm.runtimeFilter == nil) { vm.runtimeFilter = nil }
                ForEach(RuntimeLanguage.allCases) { lang in
                    let count = vm.runtimes.filter { $0.language == lang }.count
                    chip(title: "\(lang.label) (\(count))", on: vm.runtimeFilter == lang,
                         color: lang.color) {
                        vm.runtimeFilter = (vm.runtimeFilter == lang) ? nil : lang
                    }
                }
            }
            .fixedSize()
            .padding(.horizontal, Theme.hpad)
            .padding(.bottom, 10)
        }
    }

    private func chip(title: String, on: Bool, color: Color = Theme.accent,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: on ? .semibold : .regular))
                .foregroundColor(on ? .white : Theme.secondaryText)
                .padding(.horizontal, 10)
                .frame(height: Theme.controlH)              // 统一按钮高度
                .background(on ? color : Theme.cardBG)
                .cornerRadius(Theme.controlCorner)
                .overlay(RoundedRectangle(cornerRadius: Theme.controlCorner)
                    .stroke(on ? color : Theme.separator, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 列表

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(vm.visibleRuntimes) { install in
                    row(install)
                }
                if vm.visibleRuntimes.isEmpty {
                    EmptyStateView(icon: "shippingbox",
                                   title: "未检测到运行时安装",
                                   subtitle: "点击右上角「安装版本」通过 pyenv / nvm / brew 等安装。")
                        .padding(.top, 60)
                }
            }
            .padding(12)
        }
        .background(Theme.windowBG)
    }

    private func row(_ install: RuntimeInstall) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: install.language.icon)
                    .foregroundColor(install.language.color)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(install.version)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .lineLimit(1)
                        langBadge(install)
                        if install.active {
                            Text("★ 已激活")
                                .font(.caption2.weight(.bold)).foregroundColor(Theme.success)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(install.executable)
                            .font(.caption).foregroundColor(Theme.secondaryText)
                            .lineLimit(1).truncationMode(.middle)
                        if !install.environments.isEmpty {
                            Text("· \(install.environments.count) 个虚拟环境")
                                .font(.caption).foregroundColor(Theme.accent)
                        }
                    }
                }

                Spacer(minLength: 8)

                // 操作列：固定宽度对齐，徽标/按钮位置恒定，窄窗口不被挤压
                HStack(spacing: 6) {
                    if !install.active {
                        Button("激活") { confirmActivate(install) }
                            .buttonStyle(EnvButtonStyle(kind: .bordered, hpad: 10))
                    }
                    if install.uninstallable {
                        Button("卸载") { confirmUninstall(install) }
                            .buttonStyle(EnvButtonStyle(kind: .bordered, hpad: 10, color: Theme.danger))
                    } else {
                        Image(systemName: "lock")
                            .font(.caption)
                            .foregroundColor(Theme.secondaryText.opacity(0.5))
                            .frame(height: Theme.controlH)
                            .help("系统自带或由包管理器维护，不支持在此卸载")
                    }
                }
                .frame(width: 100, alignment: .trailing)
                .fixedSize()
                .layoutPriority(2)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)

            // 虚拟环境展开区
            if !install.environments.isEmpty {
                VStack(spacing: 3) {
                    ForEach(install.environments) { env in
                        HStack(spacing: 8) {
                            Image(systemName: "shippingbox")
                                .font(.system(size: 10))
                                .foregroundColor(Theme.secondaryText)
                            Text(env.name)
                                .font(.system(.caption, design: .monospaced).weight(.medium))
                            Text(env.kind)
                                .font(.caption2).foregroundColor(.white)
                                .uniformTag()
                                .background(Theme.runtimeGray.opacity(0.7)).cornerRadius(4)
                            if let v = env.version {
                                Text(v).font(.caption2).foregroundColor(Theme.secondaryText)
                            }
                            Text(env.path)
                                .font(.caption2).foregroundColor(Theme.secondaryText)
                                .lineLimit(1).truncationMode(.middle)
                            Spacer()
                        }
                        .padding(.horizontal, 14).padding(.vertical, 4)
                        .background(Theme.subtleBG)
                        .cornerRadius(6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 9)
            }
        }
        .background(install.active ? Theme.success.opacity(0.08) : Theme.cardBG)
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8)
            .stroke(install.active ? Theme.success.opacity(0.4) : Theme.separator, lineWidth: 1))
    }

    private func langBadge(_ install: RuntimeInstall) -> some View {
        Text("\(install.language.label) · \(install.sourceLabel)")
            .font(.caption2).foregroundColor(.white)
            .uniformTag()
            .background(install.language.color).cornerRadius(5)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle").foregroundColor(Theme.accent)
            Text("激活会在 ~/.zshrc 写入按语言分块的受管 PATH（Java 额外设置 JAVA_HOME），新开终端生效；卸载仅对版本管理器安装开放，删除前请确认。")
                .font(.caption).foregroundColor(Theme.secondaryText)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.06))
    }

    // MARK: - 确认

    private func confirmActivate(_ install: RuntimeInstall) {
        let alert = NSAlert()
        alert.messageText = "激活 \(install.language.label) \(install.version)？"
        alert.informativeText = "将把该版本的 bin 目录写入 ~/.zshrc 受管块：\n\(install.binDir)\n\n打开新终端后生效，可随时撤销。"
        alert.addButton(withTitle: "激活")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            vm.activateRuntime(install)
        }
    }

    private func confirmUninstall(_ install: RuntimeInstall) {
        let alert = NSAlert()
        alert.messageText = "卸载 \(install.language.label) \(install.version)？"
        alert.informativeText = "将永久删除以下目录（不可撤销，请确认其中没有重要数据）：\n" +
            install.uninstallPaths.joined(separator: "\n")
        alert.alertStyle = .warning
        alert.addButton(withTitle: "卸载")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            vm.uninstallRuntime(install)
        }
    }
}
