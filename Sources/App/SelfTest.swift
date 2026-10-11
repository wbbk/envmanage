import Foundation

/// 无界面自检：直接调用服务层，打印扫描/去重/Python 结果，用于验证核心逻辑。
enum SelfTest {
    static func run() {
        let scanner = ShellConfigService()
        let entries = scanner.scanAll()
        var sys = 0, usr = 0, rtn = 0
        for e in entries {
            switch e.scope {
            case .system: sys += 1
            case .user: usr += 1
            case .runtime: rtn += 1
            }
        }
        print("扫描：共 \(entries.count) 条（系统 \(sys) / 用户 \(usr) / 运行时 \(rtn)）")

        let grouped = scanner.groupByName(entries)
        let dups = DuplicateService().findDuplicates(
            grouped: grouped, runtimePath: scanner.effectiveValue(of: "PATH"))
        print("重复：\(dups.count) 组")
        for g in dups {
            let kind = g.kind == .scalar ? "标量" : "PATH目录"
            print("  - \(g.name) [\(kind)] 定义数=\(g.definitions.count) 保留下标=\(g.keepIndex)")
        }

        let runtimes = RuntimeService(store: FileStore()).detectAll()
        print("运行时：\(runtimes.count) 个")
        for p in runtimes {
            print("  - [\(p.language.label)] \(p.version) \(p.sourceLabel) \(p.active ? "★激活" : "") \(p.executable) 可卸载=\(p.uninstallable) 虚拟环境=\(p.environments.count)")
        }

        let paths = PathService().buildEntries()
        let missing = paths.filter { !$0.exists }.count
        print("PATH：\(paths.count) 项，缺失 \(missing) 项")

        // 敏感值遮蔽（F02-06）
        let secretCount = entries.filter { $0.isSensitive }.count
        print("敏感变量：\(secretCount) 条（默认遮蔽）")
        let probe = EnvironmentVariable(name: "GITHUB_TOKEN", rawValue: "ghp_" + String(repeating: "a1B2", count: 12),
                                        scope: .user, source: "~/.zshrc", sourceType: .export,
                                        lineNo: 1, enabled: true, priority: 50)
        print("  遮蔽示例：\(probe.name) → \(probe.maskedValue)（isSensitive=\(probe.isSensitive)）")

        // 值展开预览（F02-05）
        let expanded = ValueExpander.expand("$HOME/bin:$JAVA_HOME")
        print("值展开：'$HOME/bin:$JAVA_HOME' → '\(expanded)'")

        // 命令查找器（F04-06）
        let res = CommandResolver.resolve("python3")
        print("命令查找 python3：命中 \(res.hits.count) 处，第一命中=\(res.firstHit?.path ?? "无")，遮蔽=\(res.hasShadowing)")
        for h in res.hits.prefix(5) {
            print("  - #\(h.order) \(h.path)\(h.isSymlink ? " → \(h.realpath)" : "")")
        }

        // ===== 增量自检：写入安全 / 分类 / fish / 受管区块 / Profile / GUI 变量 =====
        var checks = 0, failed = 0
        func check(_ ok: Bool, _ desc: String) {
            if ok { checks += 1 } else { failed += 1; print("  ❌ FAIL: \(desc)") }
        }
        let dl = DiffService.diff(before: "a\nb\nc\n", after: "a\nB\nc\n")
        check(dl.contains(where: { $0.kind == .removed && $0.text == "b" }) &&
              dl.contains(where: { $0.kind == .added && $0.text == "B" }), "diff 行级识别")
        var safeOK = true
        do { try EditService.requireSafeEditable("export FOO=bar", name: "FOO") } catch { safeOK = false }
        var unsafeRejected = false
        do { try EditService.requireSafeEditable("export FOO=bar && rm -rf /", name: "FOO") } catch { unsafeRejected = true }
        check(safeOK && unsafeRejected, "危险行拒绝原位编辑")
        check(WriteAudit.isAllowedSystemWrite("/etc/zshenv") &&
              !WriteAudit.isAllowedSystemWrite("/etc/paths"), "系统写白名单")
        check(FileStore.sha256("abc") == FileStore.sha256("abc") &&
              FileStore.sha256("abc") != FileStore.sha256("abd"), "基线哈希区分内容")
        do {
            try FileStore.self.syntaxPrecheck(content: "export A=1\nif ; then\n", asShellFileAt: "/tmp/x.zsh")
            check(false, "语法预检应拒绝非法 zsh")
        } catch { check(true, "语法预检拒绝非法 zsh") }
        let e1 = EnvironmentVariable(name: "X", rawValue: "1", scope: .user, source: "/a",
                                     sourceType: .export, lineNo: 1, enabled: true, priority: 1)
        let e2 = EnvironmentVariable(name: "X", rawValue: "1", scope: .user, source: "/b",
                                     sourceType: .export, lineNo: 1, enabled: true, priority: 2)
        let e3 = EnvironmentVariable(name: "X", rawValue: "2", scope: .user, source: "/b",
                                     sourceType: .export, lineNo: 5, enabled: true, priority: 2)
        let e4 = EnvironmentVariable(name: "X", rawValue: "9", scope: .user, source: "/a",
                                     sourceType: .export, lineNo: 9, enabled: true, priority: 1)
        check(DuplicateService.categorize([e1, e2]) == .sameValue, "D02 跨文件同值")
        check(DuplicateService.categorize([e1, e3]) == .diffValue, "D03 跨文件异值")
        check(DuplicateService.categorize([e1, e4]) == .sameFile, "D01 同文件重复")
        if let (fn, fv) = ShellConfigService.parseFishSet("set -gx JAVA_HOME \"/opt/jdk\"") {
            check(fn == "JAVA_HOME" && fv == "/opt/jdk", "fish set -gx 解析")
        } else { check(false, "fish set -gx 解析") }
        let mp = ManagedPathService(store: FileStore())
        if let mplan = try? mp.plan(["~/tools/bin", "/opt/x/bin"]) {
            check(mplan.after.contains(ManagedPathService.markBegin) &&
                  mplan.after.contains(":$PATH") && mplan.path == mp.file,
                  "受管 PATH 区块生成（不落盘）")
        } else { check(false, "受管 PATH 区块生成（不落盘）") }
        var badRejected = false
        do { _ = try mp.plan(["/ok\";rm -rf /"]) } catch { badRejected = true }
        check(badRejected, "受管 PATH 拒绝危险字符")
        let pa = EnvProfile(name: "a", createdAt: "", vars: ["A": "1", "B": "2"])
        let pb = EnvProfile(name: "b", createdAt: "", vars: ["A": "9", "C": "3"])
        let pd = ProfileService.diff(pa, pb)
        check(pd.count == 3 && pd.contains(where: { $0.kind == .changed && $0.name == "A" }) &&
              pd.contains(where: { $0.kind == .removed && $0.name == "B" }) &&
              pd.contains(where: { $0.kind == .added && $0.name == "C" }), "Profile 方案三项差异")
        var nameOK = true
        do { try GuiEnvService.requireValidName("MY_VAR2") } catch { nameOK = false }
        var nameRejected = false
        do { try GuiEnvService.requireValidName("2BAD") } catch { nameRejected = true }
        check(nameOK && nameRejected, "GUI 变量名校验")
        let tools = ToolboxService.detect()
        check(tools.contains(where: { $0.name == "ruby" || $0.name == "uv" || !$0.found }), "工具链检测产出结果")
        print("增量自检：通过 \(checks) 项，失败 \(failed) 项")

        print("SELFTEST_OK")
    }
}
