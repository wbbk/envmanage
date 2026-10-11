import AppKit

/// 使用说明窗口（原生 NSAlert）。
enum HelpWindow {
    static func open() {
        let alert = NSAlert()
        alert.messageText = "EnvManage 使用说明"
        alert.informativeText = """
        1. 颜色标识：蓝=用户级，橙=系统级，灰=运行时。
        2. 环境变量页：开关可启用/禁用；铅笔编辑值；垃圾桶删除定义；「新增变量」写入配置。
        3. 禁用原理：在源文件中用可还原标记注释该行，仅影响之后新开的终端。
        4. PATH 管理页：按生效顺序查看目录、校验是否存在、发现重复目录。
        5. 重复检测页：高亮重复定义，★ 为建议保留项，可一键禁用/删除多余项。
        6. 运行时管理页：统一管理 Python / Java / Node.js / Go / C/C++ 多版本，支持激活、卸载、安装指定版本，并展示版本下的虚拟环境。
        7. 撤销/重做：⌘Z / ⇧⌘Z；所有写操作前自动备份。
        8. 修改系统级文件时会弹出管理员授权对话框。
        """
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}
