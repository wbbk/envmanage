import Foundation

/// 受管编程语言/运行时大类：Python、Java、Node.js、Go、C/C++。
enum RuntimeLanguage: String, CaseIterable, Identifiable {
    case python
    case java
    case nodejs
    case go
    case cpp

    var id: String { rawValue }

    /// 界面展示名。
    var label: String {
        switch self {
        case .python: return "Python"
        case .java:   return "Java"
        case .nodejs: return "Node.js"
        case .go:     return "Go"
        case .cpp:    return "C / C++"
        }
    }

    /// 命令行里的可执行文件名（用于 which 判定激活版本）。
    var primaryBinary: String {
        switch self {
        case .python: return "python3"
        case .java:   return "java"
        case .nodejs: return "node"
        case .go:     return "go"
        case .cpp:    return "clang++"
        }
    }
}
