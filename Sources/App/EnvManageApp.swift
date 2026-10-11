import SwiftUI

/// EnvManage 应用入口。
///
/// 纯原生 macOS（SwiftUI）应用：不依赖任何第三方库，也不启动任何 Web 服务/浏览器。
/// 整体强制浅色主题。
@main
struct EnvManageApp: App {
    @StateObject private var vm = EnvManagerViewModel()

    init() {
        // 无界面自检模式：`EnvManage --selftest`，用于在无法显示窗口的环境下验证核心逻辑。
        if CommandLine.arguments.contains("--selftest") {
            SelfTest.run()
            exit(0)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(vm)
                .preferredColorScheme(.light)          // 浅色主题
                .frame(minWidth: 840, minHeight: 560)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            // 文件菜单
            CommandGroup(after: .newItem) {
                Button("刷新环境") { vm.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
            }

            // 撤销 / 重做
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") { vm.undoChange() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!vm.undo.canUndo)
                Button("重做") { vm.redoChange() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!vm.undo.canRedo)
            }

            // 帮助
            CommandGroup(replacing: .help) {
                Button("使用说明") { HelpWindow.open() }
            }
        }

        // 菜单栏快捷入口（F10-06）：常驻图标 + 快捷菜单
        MenuBarExtra {
            MenuBarContent(vm: vm)
        } label: {
            Image(systemName: "gearshape.2.fill")
        }
        .menuBarExtraStyle(.menu)
    }
}
