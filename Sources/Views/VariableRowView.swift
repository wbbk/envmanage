import SwiftUI

/// 单个环境变量行：开关 + 名称 + 值（敏感可遮蔽）+ 操作列（对齐）+ 作用域徽标（置尾）。
struct VariableRowView: View {
    let variable: EnvironmentVariable
    let isDuplicate: Bool
    var revealSecrets: Bool = false
    var isSelected: Bool = false
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    var onSelect: () -> Void = {}

    /// 本行临时显隐（覆盖全局开关）。
    @State private var revealed = false

    private var masked: Bool { variable.isSensitive && !revealSecrets && !revealed }

    var body: some View {
        HStack(spacing: 12) {
            // 开关 / 状态
            toggleView
                .frame(width: 46)
                .fixedSize()

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(variable.name)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundColor(Theme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if isDuplicate {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(Theme.warning)
                            .font(.caption)
                            .help("该变量存在重复定义")
                    }
                    if variable.isSensitive {
                        Image(systemName: "lock.fill")
                            .foregroundColor(Theme.warning)
                            .font(.system(size: 9))
                            .help("敏感变量，值默认遮蔽")
                    }
                }
                Text(shortSource)
                    .font(.caption)
                    .foregroundColor(Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(minWidth: 120, maxWidth: 240, alignment: .leading)

            // 值（敏感时遮蔽；优先让位压缩，窄窗口下自动截断）
            HStack(spacing: 4) {
                Text(displayedValue)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(variable.enabled ? Theme.monoText : Theme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(masked ? .tail : .middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(0)
                if variable.isSensitive {
                    Button(action: { revealed.toggle() }) {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                    }
                    .buttonStyle(EnvButtonStyle(kind: .icon(Theme.secondaryText)))
                    .fixedSize()
                    .layoutPriority(1)
                    .help(revealed ? "重新遮蔽" : "显示明文")
                }
            }
            .frame(minWidth: 60, maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)

            Spacer(minLength: 8)

            // 操作列：固定宽度保证各行按钮垂直对齐，窄窗口下不被挤压
            Group {
                if variable.isEditable {
                    HStack(spacing: 2) {
                        iconButton("square.and.pencil", help: "编辑值", action: onEdit)
                        iconButton("trash", help: "删除定义", color: Theme.danger, action: onDelete)
                    }
                } else {
                    Image(systemName: "lock")
                        .foregroundColor(Theme.secondaryText.opacity(0.5))
                        .font(.caption)
                        .frame(width: 26, height: Theme.controlH)
                        .help("运行时/系统 paths 条目只读")
                }
            }
            .frame(width: 56, alignment: .trailing)
            .fixedSize()
            .layoutPriority(2)

            // 作用域徽标统一放最后，固定宽度对齐，窄窗口下不被挤压
            ScopeBadge(scope: variable.scope)
                .frame(width: 78, alignment: .trailing)
                .fixedSize()
                .layoutPriority(2)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, Theme.hpad)
        .background(rowBackground)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.corner)
                .stroke(isSelected ? Theme.accent
                        : (isDuplicate ? Theme.warning.opacity(0.5) : Color.clear), lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var displayedValue: String {
        if variable.rawValue.isEmpty { return "（空）" }
        return masked ? variable.maskedValue : variable.rawValue
    }

    @ViewBuilder
    private var toggleView: some View {
        switch variable.sourceType {
        case .runtime:
            Image(systemName: "circle.dashed")
                .foregroundColor(Theme.secondaryText)
        case .paths:
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(Theme.success)
                .help("系统 PATH 组成项")
        case .fish:
            Image(systemName: "fish")
                .foregroundColor(Theme.secondaryText)
                .help("Fish 配置定义（set -x），只读识别")
        case .export:
            Toggle("", isOn: Binding(
                get: { variable.enabled },
                set: { _ in onToggle() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        }
    }

    private var rowBackground: Color {
        if isSelected { return Theme.accent.opacity(0.06) }
        return variable.enabled ? Theme.cardBG : Theme.subtleBG
    }

    private var shortSource: String {
        let home = NSHomeDirectory()
        let s = variable.source.replacingOccurrences(of: home, with: "~")
        if let line = variable.lineNo { return "\(s):\(line)" }
        return s
    }

    private func iconButton(_ symbol: String, help: String,
                            color: Color = Theme.accent, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
        }
        .buttonStyle(EnvButtonStyle(kind: .icon(color)))
        .help(help)
    }
}
