import Foundation

/// PATH 中的一个目录条目（用于 PATH 管理标签页展示与校验）。
struct PathEntry: Identifiable, Equatable {
    let id = UUID()

    /// 目录路径，例如 /usr/local/bin
    let directory: String
    /// 该目录在文件系统上是否真实存在。
    let exists: Bool
    /// 推断的作用域：出现在 /etc/paths 系列 => 系统；否则 => 用户。
    let scope: EnvScope
    /// 在 PATH 中的顺序（0 起，越靠前优先级越高）。
    let order: Int

    static func == (lhs: PathEntry, rhs: PathEntry) -> Bool {
        lhs.id == rhs.id
    }
}
