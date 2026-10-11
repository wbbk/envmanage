import SwiftUI

/// 写操作前的文件级 diff 变化预览（F02-07）。
/// 展示每个受影响文件的 原内容 → 新内容 行级差异，确认后才真正落盘。
struct ChangePreviewSheet: View {
    let label: String
    let plans: [FilePlan]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.gearshape.fill")
                    .foregroundColor(Theme.accent).font(.title3)
                Text("变更预览：\(label)")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(Theme.primaryText)
                Spacer()
                Text("\(plans.count) 个文件受影响")
                    .font(.caption).foregroundColor(Theme.secondaryText)
            }

            Text("保存后需新开终端生效；写入前自动备份，且可用 ⌘Z 撤销。")
                .font(.caption).foregroundColor(Theme.secondaryText)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(plans.enumerated()), id: \.offset) { _, plan in
                        fileBlock(plan)
                    }
                }
            }
            .frame(maxHeight: 360)

            HStack(spacing: 10) {
                Spacer()
                Button("取消") { onCancel() }
                    .buttonStyle(EnvButtonStyle(kind: .bordered))
                    .keyboardShortcut(.cancelAction)
                Button("应用变更") { onConfirm() }
                    .buttonStyle(EnvButtonStyle(kind: .primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 620)
        .background(Theme.windowBG)
    }

    private func fileBlock(_ plan: FilePlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundColor(Theme.primaryText)
                .lineLimit(1).truncationMode(.middle)
            let lines = DiffService.diff(before: plan.before, after: plan.after)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lines.prefix(160).enumerated()), id: \.offset) { _, l in
                        Text(diffPrefix(l.kind) + l.text)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(diffColor(l.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if lines.count > 160 {
                        Text("… 共 \(lines.count) 行，余下省略 …")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.secondaryText)
                    }
                }
                .padding(8)
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.subtleBG)
            .cornerRadius(7)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.separator, lineWidth: 1))
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBG)
        .cornerRadius(Theme.corner)
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.separator, lineWidth: 1))
    }

    private func diffPrefix(_ k: DiffLine.Kind) -> String {
        switch k {
        case .context: return "  "
        case .added:   return "+ "
        case .removed: return "- "
        }
    }

    private func diffColor(_ k: DiffLine.Kind) -> Color {
        switch k {
        case .context: return Theme.secondaryText
        case .added:   return Theme.success
        case .removed: return Theme.danger
        }
    }
}
