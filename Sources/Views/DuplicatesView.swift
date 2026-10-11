import SwiftUI
import AppKit

/// 「重复检测」视图：列出重复定义并支持一键去重。
struct DuplicatesView: View {
    @EnvironmentObject var vm: EnvManagerViewModel

    var body: some View {
        Group {
            if vm.duplicates.isEmpty {
                EmptyStateView(icon: "checkmark.seal.fill",
                               title: "未发现重复定义",
                               subtitle: "所有变量都只有单一来源，PATH 中也没有重复目录。")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.windowBG)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        banner
                        ForEach(vm.duplicates) { group in
                            groupCard(group)
                        }
                    }
                    .padding(14)
                }
                .background(Theme.windowBG)
            }
        }
    }

    private var banner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Theme.warning)
            Text("发现 \(vm.duplicates.count) 组重复。★ 为建议保留（最终生效）的定义，其余为多余项。")
                .font(.callout).foregroundColor(Theme.primaryText)
            Spacer()
            if !vm.ignoredDupNames.isEmpty {
                Button(action: { vm.restoreIgnoredDuplicates() }) {
                    Label("恢复 \(vm.ignoredDupNames.count) 条已忽略提醒", systemImage: "bell.badge")
                }
                .buttonStyle(EnvButtonStyle(kind: .bordered))
                .fixedSize()
            }
        }
        .padding(12)
        .background(Theme.warning.opacity(0.10))
        .cornerRadius(Theme.corner)
    }

    @ViewBuilder
    private func groupCard(_ group: DuplicateGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(group.category.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(Theme.accent)
                    .uniformTag()
                    .background(Theme.accent.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .fixedSize()
                Spacer(minLength: 0)
                Button(action: { vm.ignoreDuplicate(group) }) {
                    Image(systemName: "bell.slash")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.secondaryText)
                }
                .buttonStyle(EnvButtonStyle(kind: .icon(Theme.secondaryText), hpad: 8))
                .fixedSize()
                .help("忽略此类提醒，可在顶部或设置页恢复")
            }
            Text(group.category.advice)
                .font(.caption).foregroundColor(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if group.kind == .pathDir {
                Label("\(group.name) \(group.category == .stalePath ? "含失效目录" : "含重复目录")",
                      systemImage: group.category == .stalePath ? "xmark.folder" : "shippingbox.fill")
                    .font(.headline).foregroundColor(Theme.warning)
                Text(group.detail)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(3).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("提示：请到「环境变量」页编辑相应 PATH 来源，去掉问题目录段。")
                    .font(.caption).foregroundColor(Theme.secondaryText)
            } else {
                HStack {
                    Label(group.name, systemImage: "doc.on.doc.fill")
                        .font(.headline).foregroundColor(Theme.primaryText)
                        .lineLimit(1).truncationMode(.tail)
                    Text("被定义 \(group.definitions.count) 次")
                        .font(.caption).foregroundColor(Theme.secondaryText)
                        .fixedSize()
                    Spacer(minLength: 8)
                    Button(action: { vm.dedupe(group, disable: true) }) {
                        Label("禁用多余", systemImage: "eye.slash")
                    }
                    .buttonStyle(EnvButtonStyle(kind: .bordered))
                    .fixedSize()
                    Button(action: { confirmAndDelete(group) }) {
                        Label("删除多余", systemImage: "trash")
                    }
                    .buttonStyle(EnvButtonStyle(kind: .bordered, color: Theme.danger))
                    .fixedSize()
                }

                // 覆盖链证据：source:line=值 → …
                if !group.detail.isEmpty {
                    Text(group.detail)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(Theme.secondaryText)
                        .lineLimit(2).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                ForEach(Array(group.definitions.enumerated()), id: \.element.id) { idx, d in
                    definitionRow(d, keep: idx == group.keepIndex)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBG)
        .cornerRadius(Theme.corner)
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.separator, lineWidth: 1))
    }

    private func definitionRow(_ d: EnvironmentVariable, keep: Bool) -> some View {
        HStack(spacing: 8) {
            Text(keep ? "★保留" : "多余")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(keep ? Theme.success : Theme.danger)
                .frame(width: 48, alignment: .leading)
            ScopeBadge(scope: d.scope)
            Text(shorten(d.source) + ":\(d.lineNo ?? 0)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.secondaryText)
                .lineLimit(1).truncationMode(.middle)
            Spacer()
            Text(d.rawValue)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(Theme.primaryText)
                .lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: 260, alignment: .trailing)
        }
        .padding(.vertical, 4)
        .opacity(keep ? 1 : 0.85)
    }

    private func confirmAndDelete(_ group: DuplicateGroup) {
        let alert = NSAlert()
        alert.messageText = "删除多余定义？"
        alert.informativeText = "将删除 \(group.name) 除★保留外的所有定义行。\n操作会自动备份且可撤销（⌘Z）。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            vm.dedupe(group, disable: false)
        }
    }

    private func shorten(_ s: String) -> String {
        s.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
