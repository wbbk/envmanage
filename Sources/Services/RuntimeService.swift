import Foundation

/// 语言运行时统一管理编排：汇总各 Provider 检测结果、写入激活块、执行卸载。
final class RuntimeService {

    private let store: FileStore
    private let providers: [RuntimeLanguage: LanguageRuntimeProvider]

    init(store: FileStore) {
        self.store = store
        let all: [LanguageRuntimeProvider] = [
            PythonRuntimeProvider(),
            JavaRuntimeProvider(),
            NodeRuntimeProvider(),
            GoRuntimeProvider(),
            CppRuntimeProvider(),
        ]
        self.providers = Dictionary(uniqueKeysWithValues: all.map { ($0.language, $0) })
    }

    // MARK: - 检测

    /// 全部语言的安装清单。
    func detectAll() -> [RuntimeInstall] {
        RuntimeLanguage.allCases.flatMap { providers[$0]?.detect() ?? [] }
    }

    func detect(_ lang: RuntimeLanguage) -> [RuntimeInstall] {
        providers[lang]?.detect() ?? []
    }

    // MARK: - 激活（设为默认版本）

    /// 把指定版本写入 ~/.zshrc 对应语言的受管块（替换旧块），新开终端生效。
    @discardableResult
    func activate(_ install: RuntimeInstall) throws -> String {
        let target = ShellFiles.defaultUserFile
        guard let provider = providers[install.language] else {
            throw EditError("不支持的语言：\(install.language.label)")
        }
        let begin = AppInfo.runtimeMarkBegin(install.language)
        let end = AppInfo.runtimeMarkEnd(install.language)

        try store.transaction("激活 \(install.language.label) \(install.version)") {
            var content = store.read(target)
            // 清理该语言旧受管块
            removeBlock(from: &content, begin: begin, end: end)
            // 兼容清理旧版 Python 受管块
            if install.language == .python {
                removeBlock(from: &content, begin: AppInfo.pyMarkBegin, end: AppInfo.pyMarkEnd)
            }
            content = content.trimmingCharacters(in: .whitespacesAndNewlines)
            let block = "\n\n\(begin)\n# 由 EnvManage 自动生成，勿手动编辑本块内容\n" +
                provider.activationBlock(for: install) + "\n\(end)\n"
            try store.write(content: content + block, to: target)
        }
        return target
    }

    private func removeBlock(from content: inout String, begin: String, end: String) {
        if let b = content.range(of: begin),
           let e = content.range(of: end, range: b.upperBound..<content.endIndex) {
            content.removeSubrange(b.lowerBound..<e.upperBound)
        }
    }

    // MARK: - 卸载

    /// 删除版本管理器/安装目录实现的卸载。仅允许 Provider 声明的白名单路径。
    func uninstall(_ install: RuntimeInstall) throws {
        guard install.uninstallable else {
            throw EditError("该安装不支持安全卸载（系统自带或由包管理器维护，请用 brew/官方卸载器移除）。")
        }
        let fm = FileManager.default
        for path in install.uninstallPaths {
            // 安全护栏：只接受绝对路径且非危险根
            guard path.hasPrefix("/"), path.count > 3, path != NSHomeDirectory() else {
                throw EditError("卸载路径被拒绝：\(path)")
            }
            guard fm.fileExists(atPath: path) else { continue }
            if install.uninstallNeedsAdmin {
                try adminRemove(path)
            } else {
                do {
                    try fm.removeItem(atPath: path)
                } catch {
                    throw EditError("删除失败：\(error.localizedDescription)")
                }
            }
        }
    }

    private func adminRemove(_ path: String) throws {
        let cmd = "rm -rf \(ShellTool.shq(path))"
        let script = "do shell script \"\(cmd)\" with administrator privileges"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let err = Pipe()
        proc.standardError = err
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            throw EditError("无法启动授权流程：\(error.localizedDescription)")
        }
        if proc.terminationStatus != 0 {
            let data = err.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8) ?? ""
            if msg.localizedCaseInsensitiveContains("cancel") || msg.contains("-128") {
                throw EditError("已取消管理员授权，未做修改。")
            }
            throw EditError("管理员删除失败或被取消。")
        }
    }
}
