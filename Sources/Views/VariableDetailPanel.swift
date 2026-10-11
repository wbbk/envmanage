import SwiftUI
import AppKit

/// 右侧详情面板（F01-06）：展示选中定义的原始值、展开值、运行时生效值、
/// 来源与权限、同名覆盖链，并提供编辑 / 定位源文件 / 开关操作。
struct VariableDetailPanel: View {
    @EnvironmentObject var vm: EnvManagerViewModel

    var body: some View {
        Group {
            if let v = vm.selectedVariable {
                detail(v)
            } else {
                EmptyStateView(icon: "cursorarrow.click",
                               title: "未选择变量",
                               subtitle: "点击左侧任意一行查看来源、展开值与覆盖链详情。")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.windowBG)
    }

    private func detail(_ v: EnvironmentVariable) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 标题
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(v.name)
                            .font(.system(.title3, design: .monospaced).weight(.bold))
                            .foregroundColor(Theme.primaryText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(v.scope.subtitle).font(.caption).foregroundColor(Theme.secondaryText)
                    }
                    Spacer()
                    ScopeBadge(scope: v.scope)
                }

                infoCard(v)
                valueSection(v)
                outcomeCard(v)
                overrideChain(v)
                actionRow(v)
            }
            .padding(16)
        }
    }

    // MARK: - 基本信息

    private func infoCard(_ v: EnvironmentVariable) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            infoRow("来源", shorten(v.source) + (v.lineNo.map { ":\($0)" } ?? ""))
            Divider()
            infoRow("类型", typeText(v))
            Divider()
            infoRow("权限", v.isEditable ? "可编辑 / 可开关" : "只读")
            Divider()
            infoRow("定义状态", v.sourceType == .export
                    ? (v.enabled ? "已启用" : "已禁用") : "—")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBG)
        .cornerRadius(Theme.corner)
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.separator, lineWidth: 1))
    }

    private func infoRow(_ k: String, _ val: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(k).font(.caption).foregroundColor(Theme.secondaryText).frame(width: 56, alignment: .leading)
                .layoutPriority(1)
            Text(val).font(.system(.caption, design: .monospaced)).foregroundColor(Theme.primaryText)
                .lineLimit(2).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func typeText(_ v: EnvironmentVariable) -> String {
        switch v.sourceType {
        case .export: return "Shell 配置定义（export / 赋值）"
        case .paths:  return "/etc/paths 系统 PATH 组成"
        case .runtime: return "运行时进程快照"
        case .fish:   return "Fish 配置定义（set -x），只读识别"
        }
    }

    // MARK: - 值 / 展开 / 生效

    private func valueSection(_ v: EnvironmentVariable) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("值").font(.subheadline.weight(.semibold)).foregroundColor(Theme.primaryText)
            valueBox("原始", v.isSensitive && !vm.revealSecrets ? v.maskedValue : v.rawValue,
                     mono: true, copyValue: v.rawValue)
            // 展开预览（仅当含 $ 或 ~ 且展开后不同）
            let expanded = ValueExpander.expand(v.rawValue)
            if expanded != v.rawValue {
                valueBox("展开", expanded, mono: true, copyValue: expanded)
                let refs = ValueExpander.referencedNames(v.rawValue)
                if !refs.isEmpty {
                    Text("引用变量：" + refs.joined(separator: "、"))
                        .font(.caption2).foregroundColor(Theme.secondaryText)
                        .lineLimit(2).truncationMode(.tail)
                }
            }
            // 运行时生效值对照
            if let eff = vm.effectiveValue(of: v.name), v.sourceType != .runtime {
                valueBox("运行时生效", v.isSensitive && !vm.revealSecrets ? v.maskedValue : eff,
                         mono: true, copyValue: eff)
            }
        }
    }

    private func valueBox(_ label: String, _ value: String, mono: Bool, copyValue: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(label).font(.caption2).foregroundColor(Theme.secondaryText)
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(copyValue ?? value, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundColor(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("复制内容到剪贴板")
            }
            Text(value.isEmpty ? "（空）" : value)
                .font(mono ? .system(.callout, design: .monospaced) : .callout)
                .foregroundColor(Theme.primaryText)
                .lineLimit(4).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.subtleBG)
        .cornerRadius(8)
    }

    // MARK: - 写入结果 / 生效确认（F07）

    private func outcomeCard(_ v: EnvironmentVariable) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("生效确认").font(.subheadline.weight(.semibold)).foregroundColor(Theme.primaryText)
            if let outcome = vm.lastOutcome, matches(outcome, v) {
                infoRow("写入结果", outcomeText(outcome))
                Divider()
            }
            infoRow("当前状态", vm.confirmation(of: v))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBG)
        .cornerRadius(Theme.corner)
        .overlay(RoundedRectangle(cornerRadius: Theme.corner)
            .stroke(Theme.separator, lineWidth: 1))
    }

    /// 最近一次写入是否与本变量相关（按名称包在提示文本里）。
    private func matches(_ o: EnvManagerViewModel.WriteOutcome, _ v: EnvironmentVariable) -> Bool {
        let text: String
        switch o {
        case .savedNewShell(let l): text = l
        case .confirmedRuntime(let l): text = l
        case .failed(let l): text = l
        }
        return text.contains(v.name)
    }

    private func outcomeText(_ o: EnvManagerViewModel.WriteOutcome) -> String {
        switch o {
        case .savedNewShell(let l):  return "✅ 已保存「\(l)」— 新开终端后生效"
        case .confirmedRuntime(let l): return "✅ \(l) — 已与当前进程一致"
        case .failed(let l):         return "❌ 未保存：\(l)"
        }
    }

    // MARK: - 同名覆盖链

    private func overrideChain(_ v: EnvironmentVariable) -> some View {
        let defs = vm.definitions(named: v.name)
        return Group {
            if defs.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Text("同名覆盖链").font(.subheadline.weight(.semibold))
                            .fixedSize().layoutPriority(1)
                        Text("共 \(defs.count) 条定义 · 最终生效为最下方启用项")
                            .font(.caption2).foregroundColor(Theme.secondaryText)
                            .lineLimit(1).truncationMode(.tail)
                    }
                    .foregroundColor(Theme.primaryText)
                    ForEach(defs) { d in
                        let winner = d.id == defs.last(where: { $0.enabled })?.id
                        HStack(spacing: 8) {
                            Image(systemName: winner ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(winner ? Theme.success : Theme.secondaryText.opacity(0.5))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(shorten(d.source) + (d.lineNo.map { ":\($0)" } ?? ""))
                                    .font(.system(.caption, design: .monospaced)).foregroundColor(Theme.primaryText)
                                    .lineLimit(1).truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(d.isSensitive && !vm.revealSecrets ? d.maskedValue : d.rawValue)
                                    .font(.system(.caption2, design: .monospaced)).foregroundColor(Theme.secondaryText)
                                    .lineLimit(1).truncationMode(.middle)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Spacer(minLength: 4)
                            ScopeBadge(scope: d.scope)
                            if !d.enabled { Text("已禁用").font(.caption2).foregroundColor(Theme.danger) }
                        }
                        .padding(8)
                        .background(d.id == v.id ? Theme.accent.opacity(0.08) : Theme.cardBG)
                        .cornerRadius(7)
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.separator, lineWidth: 1))
                    }
                }
            }
        }
    }

    // MARK: - 操作

    private func actionRow(_ v: EnvironmentVariable) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("操作").font(.subheadline.weight(.semibold)).foregroundColor(Theme.primaryText)
            HStack(spacing: 10) {
                Button(action: { revealSource(v) }) {
                    Label("定位源文件", systemImage: "doc.viewfinder")
                }
                .buttonStyle(EnvButtonStyle(kind: .bordered))
                if v.isEditable {
                    Button(action: { vm.toggle(v) }) {
                        Label(v.enabled ? "禁用此定义" : "启用此定义",
                              systemImage: v.enabled ? "eye.slash" : "eye")
                    }
                    .buttonStyle(EnvButtonStyle(kind: .bordered))
                }
                Spacer()
            }
            if v.sourceType == .export {
                Text("提示：禁用仅注释这一条定义，可逆；同名其他来源仍可能生效。")
                    .font(.caption2).foregroundColor(Theme.secondaryText)
            }
        }
    }

    private func revealSource(_ v: EnvironmentVariable) {
        let path = ShellFiles.expand(v.source)
        if FileManager.default.fileExists(atPath: path) {
            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
        } else {
            vm.statusMessage = "⚠️ 源文件不存在：\(path)"
        }
    }

    private func shorten(_ s: String) -> String {
        s.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
