import SwiftUI
import AppKit

/// 「项目环境」视图（批次③）：
/// - 项目环境文件识别（F10-03，.env/.python-version/.envrc 等，只读+信任模型说明）
/// - 虚拟环境 venv 创建/删除（F06-09）
/// - 工具链只读检测（F10-08，uv/mise/jenv/Ruby 等）
struct ProjectEnvView: View {
    @EnvironmentObject var vm: EnvManagerViewModel
    @State private var venvPath = "~/projects/demo/.venv"
    @State private var selectedPython = ""

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                projectSection
                venvSection
                toolboxSection
            }
            .padding(16)
        }
        .background(Theme.windowBG)
        .onAppear {
            if vm.toolboxes.isEmpty { vm.refresh() }
        }
    }

    // MARK: - 项目环境识别（F10-03）

    private var projectSection: some View {
        card(title: "项目环境文件识别", icon: "folder.magnifyingglass",
             note: "只读展示，绝不执行/导入。敏感值已遮蔽；.envrc 需 direnv 显式信任才生效。") {
            HStack(spacing: 8) {
                Button(action: chooseDir) {
                    Label("选择项目目录…", systemImage: "file.and.folder")
                }
                .buttonStyle(EnvButtonStyle(kind: .primary))
                .fixedSize()
                Text(vm.projectDir.isEmpty ? "尚未选择" : shorten(vm.projectDir))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if vm.projectEnvFiles.isEmpty && !vm.projectDir.isEmpty {
                Text("该目录及其一级子目录中未发现常见环境文件。")
                    .font(.caption).foregroundColor(Theme.secondaryText)
            }
            ForEach(vm.projectEnvFiles) { f in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(f.kind.rawValue)
                            .font(.caption2.weight(.semibold)).foregroundColor(Theme.accent)
                            .uniformTag()
                            .background(Theme.accent.opacity(0.12)).cornerRadius(5)
                            .fixedSize()
                        Text(shorten(f.path))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Theme.primaryText)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(f.summary.prefix(6), id: \.self) { line in
                        Text(line)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundColor(Theme.secondaryText)
                            .lineLimit(1).truncationMode(.middle)
                    }
                    if f.summary.count > 6 {
                        Text("… 共 \(f.summary.count) 行")
                            .font(.caption2).foregroundColor(Theme.secondaryText.opacity(0.7))
                    }
                    Text(f.note)
                        .font(.caption2).foregroundColor(Theme.warning.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.subtleBG)
                .cornerRadius(7)
            }
        }
    }

    private func chooseDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "扫描此目录"
        if panel.runModal() == .OK, let url = panel.url {
            vm.scanProject(dir: url.path)
        }
    }

    // MARK: - venv 管理（F06-09）

    private var pythonCandidates: [String] {
        let fromRuntimes = vm.runtimes.filter { $0.language == .python }.map(\.executable)
        let fallback = ["/usr/bin/python3", "/usr/local/bin/python3", "/opt/homebrew/bin/python3"]
        var seen = Set<String>()
        return (fromRuntimes + fallback).filter {
            $0.isEmpty ? false : seen.insert($0).inserted
        }
    }

    private var venvSection: some View {
        card(title: "Python 虚拟环境（venv）", icon: "leaf.fill",
             note: "创建使用 `<python> -m venv`；删除仅限包含 pyvenv.cfg 的目录，防误删。") {
            HStack(spacing: 8) {
                Button(action: { vm.discoverVenvs() }) {
                    Label("搜索已有 venv", systemImage: "magnifyingglass")
                }
                .buttonStyle(EnvButtonStyle(kind: .bordered)).fixedSize()
                if vm.isBusy { ProgressView().controlSize(.small) }
                Spacer()
                Text("已发现 \(vm.venvs.count) 个")
                    .font(.caption).foregroundColor(Theme.secondaryText).fixedSize()
            }

            if !vm.venvs.isEmpty {
                ForEach(vm.venvs.prefix(40)) { info in
                    HStack(spacing: 8) {
                        Image(systemName: "leaf").foregroundColor(Theme.success)
                            .frame(width: 18)
                        Text(shorten(info.path))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(Theme.primaryText)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(info.pythonVersion ?? "?")
                            .font(.caption2).foregroundColor(Theme.secondaryText)
                            .uniformTag()
                            .background(Theme.subtleBG).cornerRadius(5)
                            .fixedSize()
                        Button(action: { confirmDelete(info) }) {
                            Image(systemName: "trash").font(.system(size: 11))
                        }
                        .buttonStyle(EnvButtonStyle(kind: .icon(Theme.danger), hpad: 8))
                        .fixedSize()
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()
            HStack(spacing: 8) {
                Text("基础解释器")
                    .font(.caption).foregroundColor(Theme.secondaryText).fixedSize()
                Picker("", selection: $selectedPython) {
                    ForEach(pythonCandidates, id: \.self) { p in
                        Text(shorten(p)).tag(p)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 260)
            }
            HStack(spacing: 8) {
                TextField("venv 路径，如 ~/code/demo/.venv", text: $venvPath)
                    .textFieldStyle(.plain).uniformInput()
                Button(action: createVenv) {
                    Label("创建", systemImage: "plus.circle")
                }
                .buttonStyle(EnvButtonStyle(kind: .primary)).fixedSize()
                .disabled(selectedPython.isEmpty || venvPath.trimmingCharacters(in: .whitespaces).isEmpty
                          || vm.isInstalling)
            }
            if vm.isInstalling {
                Text("正在创建…（输出见下方）")
                    .font(.caption).foregroundColor(Theme.accent)
            } else if !vm.installLog.isEmpty {
                Text(vm.installLog)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(8)
                    .truncationMode(.head)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func createVenv() {
        vm.createVenv(pythonExe: selectedPython,
                      path: (venvPath as NSString).expandingTildeInPath)
    }

    private func confirmDelete(_ info: VenvService.Info) {
        let alert = NSAlert()
        alert.messageText = "删除虚拟环境？"
        alert.informativeText = "将永久删除目录（不经回收站）：\n\(info.path)\n\n请确认其中没有未提交的代码。"
        alert.addButton(withTitle: "删除目录")
        alert.addButton(withTitle: "取消")
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            vm.deleteVenv(info)
        }
    }

    // MARK: - 工具链检测（F10-08，只读）

    private var toolboxSection: some View {
        card(title: "版本管理工具链检测（只读）", icon: "wrench.and.screwdriver",
             note: "uv / mise / jenv / rbenv / Ruby 等 — 仅检测展示，激活管理仍由「运行时管理」页负责。") {
            if vm.toolboxes.isEmpty {
                Text("刷新后显示检测结果。")
                    .font(.caption).foregroundColor(Theme.secondaryText)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 8)], alignment: .leading,
                          spacing: 8) {
                    ForEach(vm.toolboxes) { t in
                        HStack(spacing: 7) {
                            Image(systemName: t.found ? "largecircle.fill.circle" : "circle")
                                .foregroundColor(t.found ? Theme.success : Theme.secondaryText.opacity(0.5))
                                .font(.system(size: 10))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(t.name)
                                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                                    .foregroundColor(t.found ? Theme.primaryText : Theme.secondaryText)
                                    .lineLimit(1).truncationMode(.tail)
                                Text(t.found ? (t.version ?? t.name) : "未安装")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(Theme.secondaryText)
                                    .lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 0)
                            Text(t.category)
                                .font(.caption2).foregroundColor(Theme.accent)
                                .uniformTag()
                                .background(Theme.accent.opacity(0.10)).cornerRadius(5)
                                .fixedSize()
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.subtleBG)
                        .cornerRadius(7)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.separator, lineWidth: 1))
                    }
                }
            }
        }
    }

    // MARK: - 通用

    @ViewBuilder
    private func card<Content: View>(title: String, icon: String, note: String,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.headline).foregroundColor(Theme.primaryText)
            Text(note)
                .font(.caption).foregroundColor(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBG)
        .cornerRadius(Theme.corner)
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.separator, lineWidth: 1))
    }

    private func shorten(_ s: String) -> String {
        s.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
