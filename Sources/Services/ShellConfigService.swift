import Foundation

/// 扫描引擎：解析系统级 / 用户级 shell 配置、/etc/paths，以及运行时环境，
/// 统一产出 `EnvironmentVariable` 列表。
struct ShellConfigService {

    // MARK: - 对外主入口

    /// 执行一次完整扫描，返回所有来源的变量条目。
    func scanAll() -> [EnvironmentVariable] {
        var result: [EnvironmentVariable] = []

        // 系统级 shell 文件
        for (i, path) in ShellFiles.systemFiles.enumerated() {
            result += parseShellFile(path: path, scope: .system, priority: 10 + i)
        }

        // /etc/paths 与 /etc/paths.d
        result += parsePathsFiles()

        // 用户级 shell 文件
        for (i, path) in ShellFiles.userFiles.enumerated() {
            result += parseShellFile(path: path, scope: .user, priority: 50 + i)
        }

        // 运行时（真实生效值）
        result += runtimeEntries()

        return result
    }

    /// 按变量名分组。
    func groupByName(_ entries: [EnvironmentVariable]) -> [String: [EnvironmentVariable]] {
        var dict: [String: [EnvironmentVariable]] = [:]
        for e in entries { dict[e.name, default: []].append(e) }
        return dict
    }

    // MARK: - shell 文件解析

    /// 解析一个 shell 配置文件中的 export / 赋值语句。
    ///
    /// 为避免把函数体内的局部变量误当作环境变量，仅收录：
    /// - 显式 `export NAME=...` 的行；
    /// - 或该文件中确被 `export` 过的裸赋值变量；
    /// - 以及特殊变量 PATH。
    func parseShellFile(path: String, scope: EnvScope, priority: Int) -> [EnvironmentVariable] {
        var entries: [EnvironmentVariable] = []
        let real = ShellFiles.expand(path)
        guard FileManager.default.fileExists(atPath: real),
              let content = try? String(contentsOfFile: real, encoding: .utf8) else {
            return entries
        }
        let lines = content.components(separatedBy: .newlines)
        let isFish = real.lowercased().hasSuffix(".fish")

        // 第一遍：收集本文件中被 export 过的变量名
        var exportedNames = Set<String>()
        for raw in lines {
            let body = raw.trimmingCharacters(in: .whitespaces)
            if body.hasPrefix("#") { continue }
            for name in exportNames(in: body) { exportedNames.insert(name) }
        }

        for (idx, raw) in lines.enumerated() {
            let lineNo = idx + 1
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            var enabled = true
            var body = trimmed

            if body.hasPrefix(AppInfo.disableMarker) {
                body = String(body.dropFirst(AppInfo.disableMarker.count))
                    .trimmingCharacters(in: .whitespaces)
                enabled = false
            } else if body.hasPrefix("#") {
                continue
            }

            let parsed: (String, String, Bool)?
            if isFish {
                if let (n, v) = Self.parseFishSet(body) { parsed = (n, v, true) } else { parsed = nil }
            } else {
                parsed = Self.parseAssignment(body)
            }
            guard let (name, value, isExport) = parsed else { continue }
            if Self.blockedNames.contains(name) { continue }
            if !isFish && !isExport && name != "PATH" && !exportedNames.contains(name) { continue }

            entries.append(EnvironmentVariable(
                name: name, rawValue: value, scope: scope, source: real,
                sourceType: isFish ? .fish : .export, lineNo: lineNo, enabled: enabled, priority: priority))
        }
        return entries
    }

    /// 从一行中提取 `export` 后面紧跟的变量名（可能有多个）。
    private func exportNames(in line: String) -> [String] {
        var names: [String] = []
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        var i = 0
        while i < parts.count {
            if parts[i] == "export" {
                var j = i + 1
                // 跳过 -f / -- 之类选项
                while j < parts.count, parts[j].hasPrefix("-") { j += 1 }
                if j < parts.count {
                    let token = String(parts[j])
                    let nm = token.components(separatedBy: "=")[0]
                    if Self.isValidIdentifier(nm) { names.append(nm) }
                }
                i = j
            }
            i += 1
        }
        return names
    }

    /// 解析 fish 的 `set -x/-gx/-U NAME value…` 定义行（F10-07，只读识别）。
    /// PATH 类变量用冒号拼接展示，其余以空格拼接。
    static func parseFishSet(_ line: String) -> (String, String)? {
        guard line.hasPrefix("set ") else { return nil }
        var toks = line.dropFirst(4).split(separator: " ", omittingEmptySubsequences: true)
            .map(String.init)
        let flags: Set<String> = ["-x", "-gx", "-U", "-u", "-l", "-g", "--export"]
        toks.removeAll { flags.contains($0) }
        guard let name = toks.first, isValidIdentifier(name), !blockedNames.contains(name) else { return nil }
        let values = toks.dropFirst().map { stripQuotes($0) }
        let sep = (name == "PATH" || name.hasSuffix("_PATH")) ? ":" : " "
        return (name, values.joined(separator: sep))
    }

    /// 解析 export / 赋值行，返回 (name, value, isExport)。
    static func parseAssignment(_ body: String) -> (String, String, Bool)? {
        var work = body
        var isExport = false
        if work.hasPrefix("export ") {
            isExport = true
            work = String(work.dropFirst("export ".count))
        }
        guard let eq = work.firstIndex(of: "=") else { return nil }
        let name = String(work[work.startIndex..<eq])
        var value = String(work[work.index(after: eq)...])
        if !isValidIdentifier(name) { return nil }
        value = stripQuotes(value)
        return (name, value, isExport)
    }

    static func stripQuotes(_ v: String) -> String {
        var s = v.trimmingCharacters(in: .whitespaces)
        if s.count >= 2,
           let f = s.first, let l = s.last, f == l, f == "\"" || f == "'" {
            s = String(s.dropFirst().dropLast())
        }
        return s
    }

    static func isValidIdentifier(_ s: String) -> Bool {
        guard !s.isEmpty, let first = s.first else { return false }
        guard first.isLetter || first == "_" else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    static let blockedNames: Set<String> = [
        "alias", "path", "fpath", "local", "then", "else", "fi",
        "do", "done", "if", "for", "while", "case", "esac", "function",
    ]

    // MARK: - /etc/paths

    func parsePathsFiles() -> [EnvironmentVariable] {
        var entries: [EnvironmentVariable] = []
        let fm = FileManager.default
        var sources: [String] = []
        if fm.fileExists(atPath: "/etc/paths") { sources.append("/etc/paths") }
        if let items = try? fm.contentsOfDirectory(atPath: "/etc/paths.d") {
            sources += items.sorted().map { "/etc/paths.d/" + $0 }
        }
        for src in sources {
            guard let content = try? String(contentsOfFile: src, encoding: .utf8) else { continue }
            for (idx, line) in content.components(separatedBy: .newlines).enumerated() {
                let val = line.trimmingCharacters(in: .whitespaces)
                if val.isEmpty || val.hasPrefix("#") { continue }
                entries.append(EnvironmentVariable(
                    name: "PATH", rawValue: val, scope: .system, source: src,
                    sourceType: .paths, lineNo: idx + 1, enabled: true, priority: 0))
            }
        }
        return entries
    }

    // MARK: - 运行时

    func runtimeEntries() -> [EnvironmentVariable] {
        var entries: [EnvironmentVariable] = []
        for (k, v) in ProcessInfo.processInfo.environment {
            entries.append(EnvironmentVariable(
                name: k, rawValue: v, scope: .runtime, source: "当前进程 (运行时)",
                sourceType: .runtime, lineNo: nil, enabled: true, priority: 100))
        }
        return entries
    }

    /// 运行时某变量的真实生效值。
    func effectiveValue(of name: String) -> String? {
        ProcessInfo.processInfo.environment[name]
    }
}
