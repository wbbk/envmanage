import Foundation

/// 每种语言的运行时提供者统一协议：检测安装、生成激活片段。
/// 由 RuntimeService 汇总调度，Provider 本身无状态、可并发调用。
protocol LanguageRuntimeProvider {
    var language: RuntimeLanguage { get }

    /// 扫描本机该语言的所有安装（含虚拟环境挂载）。
    func detect() -> [RuntimeInstall]

    /// 生成写入 ~/.zshrc 受管块的 shell 片段（PATH 前置 / JAVA_HOME 等）。
    func activationBlock(for install: RuntimeInstall) -> String

    /// 判定哪个安装是当前默认（which 解析真实路径比对）。
    func markActive(_ installs: inout [RuntimeInstall])
}

extension LanguageRuntimeProvider {
    /// 默认激活实现：把 binDir 前置到 PATH。
    func activationBlock(for install: RuntimeInstall) -> String {
        "export PATH=\"\(install.binDir):$PATH\""
    }

    /// 默认激活判定：which(主二进制) 解析符号链接后与 executable 比对。
    func markActive(_ installs: inout [RuntimeInstall]) {
        guard let hit = ShellTool.which(language.primaryBinary) else { return }
        let real = (hit as NSString).resolvingSymlinksInPath
        for i in installs.indices where installs[i].executable == real {
            installs[i].active = true
        }
    }

    /// 语义化版本号降序比较（用于列表排序）。
    func versionCompare(_ a: String, _ b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
