import Foundation

/// 跨 Provider 共享的 shell 工具函数：which / 命令捕获 / glob / 流式执行。
enum ShellTool {

    /// 在 PATH 中查找可执行文件。
    static func which(_ name: String) -> String? {
        guard let path = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        for dir in path.split(separator: ":") {
            let cand = String(dir) + "/" + name
            if FileManager.default.isExecutableFile(atPath: cand) { return cand }
        }
        return nil
    }

    /// 判断命令是否可用（which 或指定路径存在）。
    static func available(_ name: String) -> Bool {
        which(name) != nil
    }

    /// 同步执行并捕获 stdout+stderr（trimmed）。
    static func runCapture(_ launchPath: String, _ args: [String]) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: launchPath)
        proc.arguments = args
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 通过 zsh 登录 shell 异步执行命令串，逐行回调输出（主线程），结束后回调退出码。
    /// 用于 nvm / sdkman 等需要先 source 初始化脚本的版本管理器。
    static func runShellAsync(_ command: String,
                              onLine: @escaping (String) -> Void,
                              onDone: @escaping (Int32) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
            proc.arguments = ["-c", command]
            // GUI 进程（Finder/open 启动）的 PATH 不含 Homebrew 等目录，
            // 子 shell 需补齐常见安装路径，否则 brew/curl 等命令找不到。
            var env = ProcessInfo.processInfo.environment
            var dirs = (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
                .split(separator: ":").map(String.init)
            for extra in ["/opt/homebrew/bin", "/usr/local/bin"] where !dirs.contains(extra) {
                dirs.append(extra)
            }
            env["PATH"] = dirs.joined(separator: ":")
            proc.environment = env
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty,
                      let text = String(data: data, encoding: .utf8) else { return }
                for line in text.components(separatedBy: .newlines) where !line.isEmpty {
                    DispatchQueue.main.async { onLine(line) }
                }
            }
            do {
                try proc.run()
                proc.waitUntilExit()
                pipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async { onDone(proc.terminationStatus) }
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async {
                    onLine("执行失败：\(error.localizedDescription)")
                    onDone(-1)
                }
            }
        }
    }

    /// Darwin C glob() 文件通配（SDK 无 FileManager.glob）。
    static func glob(_ pattern: String) -> [String] {
        var gt = glob_t()
        defer { globfree(&gt) }
        guard Darwin.glob(pattern, 0, nil, &gt) == 0 else { return [] }
        var results: [String] = []
        for i in 0..<Int(gt.gl_matchc) {
            if let ptr = gt.gl_pathv[i] {
                results.append(String(cString: ptr))
            }
        }
        return results
    }

    static func isDir(_ p: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: p, isDirectory: &isDir) && isDir.boolValue
    }

    /// shell 单引号转义。
    static func shq(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
