import SwiftUI

/// 浅色主题调色板与语义色。
///
/// 应用整体强制浅色（见 EnvManageApp 的 preferredColorScheme(.light)），
/// 这里给出统一、克制的浅色系配色，贴近参考项目 peervw/envmanager 的原生质感。
enum Theme {
    // 背景层
    static let windowBG   = Color(nsColor: .windowBackgroundColor)       // 浅灰主背景
    static let cardBG     = Color(nsColor: .textBackgroundColor)         // 白色卡片
    static let subtleBG   = Color(nsColor: .controlBackgroundColor)
    static let separator  = Color(nsColor: .separatorColor)

    // 文字
    static let primaryText   = Color(nsColor: .labelColor)
    static let secondaryText = Color(nsColor: .secondaryLabelColor)
    static let monoText      = Color(nsColor: .labelColor)

    // 强调 / 语义
    static let accent   = Color(nsColor: .controlAccentColor)            // 系统蓝
    static let success  = Color(red: 0.20, green: 0.66, blue: 0.32)      // 绿
    static let warning  = Color(red: 0.94, green: 0.55, blue: 0.10)      // 橙
    static let danger   = Color(red: 0.86, green: 0.24, blue: 0.24)      // 红
    static let runtimeGray = Color(nsColor: .systemGray)

    /// 圆角与间距。
    static let corner: CGFloat = 10
    static let hpad: CGFloat = 14

    /// 统一控件高度规格：所有按钮 / 输入框 / 分段切换等高。
    static let controlH: CGFloat = 26
    /// 统一标签（tag）/徽标高度。
    static let badgeH: CGFloat = 20
    /// 统一控件圆角。
    static let controlCorner: CGFloat = 7
}

/// 作用域 -> 颜色 / 图标 的语义映射（区分系统与用户的关键视觉标识）。
extension EnvScope {
    var color: Color {
        switch self {
        case .system:  return Theme.warning      // 系统级 = 橙
        case .user:    return Theme.accent       // 用户级 = 蓝
        case .runtime: return Theme.runtimeGray  // 运行时 = 灰
        }
    }

    var icon: String {
        switch self {
        case .system:  return "gearshape.2.fill"
        case .user:    return "person.crop.circle.fill"
        case .runtime: return "cpu"
        }
    }
}

/// 语言 -> 图标 / 颜色 的语义映射（运行时管理页使用）。
extension RuntimeLanguage {
    var icon: String {
        switch self {
        case .python: return "curlybraces"
        case .java:   return "cup.and.saucer.fill"
        case .nodejs: return "hexagon.fill"
        case .go:     return "bird.fill"
        case .cpp:    return "hammer.fill"
        }
    }

    var color: Color {
        switch self {
        case .python: return Color(red: 0.25, green: 0.45, blue: 0.75)   // 深蓝
        case .java:   return Color(red: 0.80, green: 0.45, blue: 0.15)   // 棕橙
        case .nodejs: return Color(red: 0.30, green: 0.62, blue: 0.35)   // 绿
        case .go:     return Color(red: 0.15, green: 0.60, blue: 0.80)   // 天蓝
        case .cpp:    return Color(red: 0.45, green: 0.40, blue: 0.75)   // 紫
        }
    }
}
