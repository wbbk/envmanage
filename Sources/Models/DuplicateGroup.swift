import Foundation

/// 重复定义的类型。
enum DuplicateKind {
    case scalar    // 同一变量被多次 export
    case pathDir   // 运行时 PATH 中存在重复/失效目录
}

/// 重复的分类（F05）：区分成因，给出针对性建议。
enum DupCategory: String {
    case sameFile    // D01 同一文件内重复定义
    case sameValue   // D02 跨文件重复但值一致
    case diffValue   // D03 跨文件重复且值不一致
    case pathDir     // D04 PATH 含重复目录
    case stalePath   // D06 PATH 含失效目录

    var label: String {
        switch self {
        case .sameFile:  return "D01 · 同文件重复"
        case .sameValue: return "D02 · 跨文件同值"
        case .diffValue: return "D03 · 跨文件异值"
        case .pathDir:   return "D04 · PATH 重复目录"
        case .stalePath: return "D06 · PATH 失效目录"
        }
    }

    var advice: String {
        switch self {
        case .sameFile:
            return "同一文件内出现多次定义，仅最后一次生效，建议禁用或删除其余行。"
        case .sameValue:
            return "多处定义值一致，风险较低；清理后可减少覆盖链噪音。"
        case .diffValue:
            return "多处定义值不一致，最终以加载靠后的为准；请确认保留项，禁用其余避免困惑。"
        case .pathDir:
            return "运行时 PATH 中存在重复目录，会拖慢命令查找；请到相应来源去掉重复目录段。"
        case .stalePath:
            return "PATH 中存在实际不存在的目录，多来自已卸载工具；建议从来源中移除。"
        }
    }
}

/// 一组重复定义。
struct DuplicateGroup: Identifiable {
    let id = UUID()

    let name: String
    let kind: DuplicateKind
    /// 重复成因分类。
    let category: DupCategory
    /// 参与重复的可编辑定义（kind == .scalar 时有效）。
    let definitions: [EnvironmentVariable]
    /// 建议保留的定义在 definitions 中的下标（pathDir 时为 -1）。
    let keepIndex: Int
    /// 附加说明，如重复/失效的 PATH 目录列表。
    var detail: String
    /// 覆盖链证据文本（source:line=值 → …），scalar 组展示用。
    var evidence: String = ""
}
