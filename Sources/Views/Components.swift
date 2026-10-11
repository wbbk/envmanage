import SwiftUI

/// 统一控件规格修饰器。
extension View {
    /// 统一标签/徽标高度（Theme.badgeH）；需置于 `.background` 之前使用。
    func uniformTag() -> some View {
        frame(height: Theme.badgeH).padding(.horizontal, 7)
    }
    /// 统一输入框外观：固定高度 Theme.controlH + 底色 + 描边。
    func uniformInput() -> some View {
        padding(.horizontal, 8)
            .frame(height: Theme.controlH)
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(Theme.controlCorner)
            .overlay(RoundedRectangle(cornerRadius: Theme.controlCorner)
                .stroke(Theme.separator, lineWidth: 1))
    }
}

/// 全局统一高度的按钮样式：primary（强调底）/ bordered（描边）/ icon（正方形图标）。
struct EnvButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case bordered
        case icon(Color)
    }
    var kind: Kind = .bordered
    var hpad: CGFloat = 12
    var color: Color = Theme.primaryText

    func makeBody(configuration: Configuration) -> some View {
        EnvButtonBody(configuration: configuration, kind: kind, hpad: hpad, color: color)
    }

    private struct EnvButtonBody: View {
        let configuration: Configuration
        let kind: Kind
        let hpad: CGFloat
        let color: Color
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            content
                .opacity(isEnabled ? 1 : 0.45)   // 置灰态统一处理
        }

        @ViewBuilder
        private var content: some View {
            switch kind {
            case .primary:
                configuration.label
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, hpad)
                    .frame(height: Theme.controlH)
                    .foregroundColor(.white)
                    .background(Theme.accent.opacity(configuration.isPressed ? 0.7 : 1))
                    .cornerRadius(Theme.controlCorner)
            case .bordered:
                configuration.label
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, hpad)
                    .frame(height: Theme.controlH)
                    .foregroundColor(color)
                    .background(Color(nsColor: .controlBackgroundColor)
                        .opacity(configuration.isPressed ? 0.55 : 1))
                    .cornerRadius(Theme.controlCorner)
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlCorner)
                        .stroke(Theme.separator, lineWidth: 1))
            case .icon(let tint):
                configuration.label
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: Theme.controlH, height: Theme.controlH)
                    .foregroundColor(tint)
                    .background(Color(nsColor: .controlBackgroundColor)
                        .opacity(configuration.isPressed ? 0.55 : 1))
                    .cornerRadius(Theme.controlCorner)
                    .overlay(RoundedRectangle(cornerRadius: Theme.controlCorner)
                        .stroke(Theme.separator, lineWidth: 1))
            }
        }
    }
}

/// 统一高度的分段切换（替代原生 segmented Picker，与按钮/输入框等高）。
struct SegmentedToggle<T: Hashable>: View {
    let options: [(label: String, tag: T)]
    @Binding var selection: T

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.tag) { opt in
                let on = selection == opt.tag
                Button(action: { selection = opt.tag }) {
                    Text(opt.label)
                        .font(.system(size: 12, weight: on ? .semibold : .regular))
                        .foregroundColor(on ? .white : Theme.primaryText)
                        .padding(.horizontal, 10)
                        .frame(maxHeight: .infinity)
                        .background(on ? Theme.accent : Color.clear)
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .frame(height: Theme.controlH)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(Theme.controlCorner)
        .overlay(RoundedRectangle(cornerRadius: Theme.controlCorner)
            .stroke(Theme.separator, lineWidth: 1))
        .fixedSize()
    }
}

/// 作用域彩色徽标——界面上区分系统 / 用户 / 运行时的核心标识。
struct ScopeBadge: View {
    let scope: EnvScope

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: scope.icon)
                .font(.system(size: 10, weight: .bold))
            Text(scope.label)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .frame(height: Theme.badgeH)
        .background(scope.color)
        .cornerRadius(6)
    }
}

/// 通用空状态视图。
struct EmptyStateView: View {
    var icon: String = "tray"
    var title: String = "暂无内容"
    var subtitle: String = ""

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundColor(Theme.secondaryText.opacity(0.6))
            Text(title)
                .font(.headline)
                .foregroundColor(Theme.primaryText)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(Theme.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
