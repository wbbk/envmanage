import Foundation

/// 项目目录中发现的一个环境描述文件（F10-03，只读识别）。
struct ProjectEnvFile: Identifiable, Hashable {
    enum Kind: String {
        case dotenv = ".env"
        case pythonVersion = ".python-version"
        case toolVersions = ".tool-versions"
        case mise = "mise.toml"
        case envrc = ".envrc"
        case fish = "config.fish"
    }
    var id: String { path }
    let path: String
    let kind: Kind
    /// 摘要行（.env 的键名列表 / 版本行等，敏感值已遮蔽）。
    let summary: [String]
    /// 说明：该文件由谁消费、EnvManage 为何不自动应用（信任模型）。
    let note: String
}

/// 项目环境识别（F10-03）：在用户选择的项目目录浅层扫描常见环境文件，
/// 只读展示内容摘要与消费方，不自动加载（.envrc 需 direnv 且显式信任）。
enum ProjectEnvScanner {

    static let fileKinds: [(String, ProjectEnvFile.Kind)] = [
        (".env", .dotenv),
        (".env.local", .dotenv),
        (".python-version", .pythonVersion),
        (".tool-versions", .toolVersions),
        ("mise.toml", .mise),
        (".mise.toml", .mise),
        (".envrc", .envrc),
    ]

    /// 扫描一个项目目录（根 + 一级子目录），返回发现的环境文件。
    static func scan(projectDir: String) -> [ProjectEnvFile] {
        let root = (projectDir as NSString).expandingTildeInPath
        var dirs = [root]
        if let level1 = try? FileManager.default.contentsOfDirectory(atPath: root) {
            dirs += level1.prefix(80).map { root + "/" + $0 }
        }
        var results: [ProjectEnvFile] = []
        var seen = Set<String>()
        for dir in dirs {
            for (name, kind) in fileKinds {
                let p = dir + "/" + name
                guard !seen.contains(p),
                      FileManager.default.fileExists(atPath: p),
                      let f = parse(path: p, kind: kind) else { continue }
                seen.insert(p)
                results.append(f)
            }
        }
        return results.sorted { $0.path < $1.path }
    }

    private static func parse(path: String, kind: ProjectEnvFile.Kind) -> ProjectEnvFile? {
        guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var summary: [String] = []
        var note = ""
        switch kind {
        case .dotenv:
            // 只列键名与遮蔽后的值，绝不外传内容
            for line in content.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("#") { continue }
                guard let eq = t.firstIndex(of: "=") else { continue }
                let key = String(t[..<eq])
                let val = String(t[t.index(after: eq)...])
                let masked = val.count > 6 ? String(val.prefix(3)) + "…" : "•••"
                summary.append("\(key)=\(masked)")
            }
            note = "由应用/框架自行加载（如 python-dotenv）；EnvManage 只展示键名，不导入全局环境。"
        case .pythonVersion, .toolVersions:
            summary = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") }
            note = "pyenv / mise / asdf 等版本管理器的项目级版本声明；切目录时由它们自动生效。"
        case .mise:
            let miseLines = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("[") }
            summary = Array(miseLines.prefix(12))
            note = "mise 项目配置（[tools]/[env]）；由 mise 在目录内生效。"
        case .envrc:
            let rcLines = content.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            summary = Array(rcLines.prefix(12))
            note = "direnv 脚本，可执行任意命令 — 默认不受信任，EnvManage 仅展示内容，绝不执行。"
        case .fish:
            note = "Fish 项目配置。"
        }
        return ProjectEnvFile(path: path, kind: kind, summary: summary, note: note)
    }
}
