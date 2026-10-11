import Foundation

/// 一款检测到的版本管理/语言工具链（F10-08，只读）。
struct ToolboxTool: Identifiable, Hashable {
    var id: String { name }
    let name: String          // 工具名，如 uv / mise / jenv / ruby
    let category: String      // 归类：Python / 通用 / Ruby
    let version: String?      // --version 首行摘要
    let path: String?         // 可执行文件位置（生效 PATH + 常见安装位置）
    var found: Bool { path != nil }
}

/// 扩展工具链只读检测（F10-08）：uv / mise / jenv / rbenv / rvm / asdf / Ruby。
/// 只做检测与展示，不做激活管理；激活仍由既有 RuntimeService 负责。
enum ToolboxService {

    static let candidates: [(name: String, category: String)] = [
        ("uv", "Python"), ("pipx", "Python"), ("poetry", "Python"),
        ("mise", "通用"), ("asdf", "通用"),
        ("jenv", "Java"), ("sdk", "Java"),
        ("rbenv", "Ruby"), ("rvm", "Ruby"), ("ruby", "Ruby"), ("gem", "Ruby"),
    ]

    /// 常见安装目录（生效 PATH 之外的兜底搜索）。
    static let extraDirs = [
        "/usr/local/bin", "/opt/homebrew/bin",
        NSHomeDirectory() + "/.local/bin",
        NSHomeDirectory() + "/.cargo/bin",
        NSHomeDirectory() + "/.mise/bin",
        NSHomeDirectory() + "/.asdf/shims",
        NSHomeDirectory() + "/.rbenv/bin",
        NSHomeDirectory() + "/.jenv/bin",
        "/usr/bin",
    ]

    static func detect() -> [ToolboxTool] {
        let pathDirs = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":").map(String.init)
        let searchDirs = pathDirs + extraDirs

        var tools: [ToolboxTool] = []
        for (name, category) in candidates {
            let hit = searchDirs.first { dir in
                FileManager.default.isExecutableFile(atPath: dir + "/" + name)
            }
            var version: String? = nil
            if let dir = hit {
                version = readVersion(dir + "/" + name)
            }
            tools.append(ToolboxTool(name: name, category: category,
                                     version: version, path: hit.map { $0 + "/" + name }))
        }
        // 命中的排前面，同类按名称排序
        return tools.sorted {
            if $0.found != $1.found { return $0.found && !$1.found }
            if $0.category != $1.category { return $0.category < $1.category }
            return $0.name < $1.name
        }
    }

    private static func readVersion(_ exe: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = ["--version"]
        let out = Pipe()
        proc.standardOutput = out
        proc.standardError = Pipe()
        do {
            try proc.run()
        } catch { return nil }
        // 2 秒超时保护
        let deadline = Date().addingTimeInterval(2)
        while proc.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if proc.isRunning { proc.terminate(); return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let first = text.components(separatedBy: .newlines).first ?? ""
        return first.isEmpty ? nil : String(first.prefix(80))
    }
}
