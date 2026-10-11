import SwiftUI
import AppKit

/// 可下拉选择、也可手动输入筛选的版本号组合框（包装 NSComboBox）。
/// 输入内容会实时过滤下拉候选；支持选择后继续编辑。
struct VersionComboBox: NSViewRepresentable {
    var text: Binding<String>
    var options: [String]
    var placeholder: String = "选择或输入版本号"
    var isEnabled: Bool = true

    func makeCoordinator() -> Coordinator { Coordinator(text: text) }

    func makeNSView(context: Context) -> NSComboBox {
        let cb = NSComboBox()
        cb.placeholderString = placeholder
        cb.completes = true
        cb.usesDataSource = false
        cb.numberOfVisibleItems = 12
        cb.isEditable = true
        cb.delegate = context.coordinator
        // action：选中项 / 回车 / 失焦提交后触发，作为值回传的兜底通道
        cb.target = context.coordinator
        cb.action = #selector(Coordinator.comboAction(_:))
        cb.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        cb.controlSize = .regular
        return cb
    }

    func updateNSView(_ cb: NSComboBox, context: Context) {
        context.coordinator.text = text
        context.coordinator.control = cb

        // 外部值变化才回写控件，避免打断输入
        if cb.stringValue != text.wrappedValue, !context.coordinator.isUpdating {
            cb.stringValue = text.wrappedValue
        }
        let current = context.coordinator.lastOptions
        if current != options {
            cb.removeAllItems()
            options.forEach { cb.addItem(withObjectValue: $0) }
            context.coordinator.lastOptions = options
        }
        cb.isEnabled = isEnabled
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var text: Binding<String>
        weak var control: NSComboBox?
        var lastOptions: [String] = []
        var isUpdating = false

        init(text: Binding<String>) { self.text = text }

        /// 统一写回入口。
        private func commit(_ value: String) {
            isUpdating = true
            text.wrappedValue = value
            isUpdating = false
        }

        // 手动输入路径
        func controlTextDidChange(_ notification: Notification) {
            guard let cb = control, !isUpdating else { return }
            commit(cb.stringValue)
        }

        // 下拉选中路径：通知触发时 stringValue 可能还是旧值，
        // 必须从 indexOfSelectedItem + itemObjectValue 取选中项。
        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let cb = control, !isUpdating else { return }
            let idx = cb.indexOfSelectedItem
            if idx >= 0, let item = cb.itemObjectValue(at: idx) as? String {
                commit(item)
            } else {
                // 取消选择等场景：延后一拍再读 stringValue
                DispatchQueue.main.async { [weak self, weak cb] in
                    guard let self, let cb, !self.isUpdating else { return }
                    self.commit(cb.stringValue)
                }
            }
        }

        // action 兜底：回车 / 失焦提交
        @objc func comboAction(_ sender: NSComboBox) {
            commit(sender.stringValue)
        }
    }
}
