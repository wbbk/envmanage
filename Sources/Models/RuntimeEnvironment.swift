import Foundation

/// 运行时版本下的虚拟环境 / 子环境（如 Python 的 venv、Conda env）。
struct RuntimeEnvironment: Identifiable, Equatable {
    let id = UUID()

    let name: String        // 环境名
    let path: String        // 环境根目录绝对路径
    let kind: String        // "venv" / "conda env" / "virtualenv"
    var version: String?    // 环境内解释器版本（可缺省）

    static func == (lhs: RuntimeEnvironment, rhs: RuntimeEnvironment) -> Bool {
        lhs.path == rhs.path
    }
}
