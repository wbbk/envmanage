import Foundation

/// 环境变量作用域：用于界面区分「系统级 / 用户级 / 运行时」。
enum EnvScope: String, Codable, CaseIterable, Identifiable {
    case system
    case user
    case runtime

    var id: String { rawValue }

    /// 中文标识文本。
    var label: String {
        switch self {
        case .system: return "系统"
        case .user:   return "用户"
        case .runtime: return "运行时"
        }
    }

    /// 简短说明。
    var subtitle: String {
        switch self {
        case .system: return "来自 /etc 系统配置"
        case .user:   return "来自你的用户配置"
        case .runtime: return "当前进程真实生效值"
        }
    }
}

/// 变量来源类型，决定该条目能否被编辑/开关。
enum SourceType: String, Codable {
    case export    // shell 配置文件中的 export / 赋值行，可编辑可开关
    case paths     // /etc/paths 或 /etc/paths.d 的 PATH 组成，只读展示
    case runtime   // 运行时环境快照，只读对照
    case fish      // Fish 配置 set -x 定义，只读识别（F10-07）
}

/// 一条环境变量记录。
///
/// 同一变量名可能来自多个源文件，因此以 (name, source, lineNo) 为粒度保存，
/// 便于去重分析。使用 `Hashable`/`Equatable` 以便在 SwiftUI 列表与撤销栈中使用。
struct EnvironmentVariable: Identifiable, Codable, Equatable, Hashable {

    /// 稳定唯一标识：源文件 + 行号 + 变量名。
    var id: String { "\(source)#\(lineNo ?? -1)#\(name)" }

    let name: String
    let rawValue: String
    let scope: EnvScope
    let source: String
    let sourceType: SourceType
    let lineNo: Int?
    var enabled: Bool
    let priority: Int

    /// 是否为可编辑/可开关的配置定义。
    var isEditable: Bool { sourceType == .export }

    /// 敏感变量名关键字（命中则默认遮蔽值，F02-06）。
    static let sensitiveNameTokens = [
        "TOKEN", "SECRET", "PASSWORD", "PASSWD", "PASS", "KEY", "CREDS",
        "CREDENTIAL", "PRIVATE", "APIKEY", "AUTH", "CERT", "PIN",
    ]

    /// 是否敏感：变量名含敏感关键字，或值形似密钥（长随机串 / 已知前缀）。
    var isSensitive: Bool {
        let upper = name.uppercased()
        if Self.sensitiveNameTokens.contains(where: { upper.contains($0) }) { return true }
        return Self.looksLikeSecret(rawValue)
    }

    /// 值形态启发式识别密钥：私钥头、常见 token 前缀、或长度≥40 的高熵串。
    static func looksLikeSecret(_ v: String) -> Bool {
        if v.contains("PRIVATE KEY") || v.hasPrefix("-----BEGIN") { return true }
        let prefixes = ["ghp_", "gho_", "github_pat_", "xox", "sk-", "AKIA", "AIza", "Bearer "]
        if prefixes.contains(where: { v.hasPrefix($0) }) { return true }
        // 长度≥40 且几乎全是 base64/hex 字符，视为可能的密钥
        if v.count >= 40, v.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "/" || $0 == "+" || $0 == "=" || $0 == "-" || $0 == "_" }) {
            let digits = v.filter { $0.isNumber }.count
            let letters = v.filter { $0.isLetter }.count
            return digits >= 3 && letters >= 3   // 混合型高熵，排除纯路径/纯单词
        }
        return false
    }

    /// 遮蔽后的展示值（保留首 2 尾 2 便于识别，长度不足则全遮蔽）。
    var maskedValue: String {
        let v = rawValue
        if v.count <= 4 { return String(repeating: "•", count: max(v.count, 4)) }
        let head = v.prefix(2)
        let tail = v.suffix(2)
        return "\(head)\(String(repeating: "•", count: 8))\(tail)"
    }

    /// 展示用值：运行时快照直接展示，配置项展示原始写法。
    var displayValue: String { rawValue }

    /// 用于排序/去重比较的键：加载优先级 + 行号。
    var orderKey: (Int, Int) { (priority, lineNo ?? 0) }

    enum CodingKeys: String, CodingKey {
        case name, rawValue, scope, source, sourceType, lineNo, enabled, priority
    }
}
