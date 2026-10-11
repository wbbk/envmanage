import SwiftUI

/// 新增变量弹窗。
struct AddVariableSheet: View {
    @EnvironmentObject var vm: EnvManagerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var value: String = ""
    @State private var userScope: Bool = true
    @State private var errorText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("新增环境变量")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("变量名").font(.caption).foregroundColor(Theme.secondaryText)
                TextField("例如 MY_HOME", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .uniformInput()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("值").font(.caption).foregroundColor(Theme.secondaryText)
                TextField("例如 /opt/foo", text: $value)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .uniformInput()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("写入位置").font(.caption).foregroundColor(Theme.secondaryText)
                Picker("", selection: $userScope) {
                    Text("用户级  (~/.zshrc)").tag(true)
                    Text("系统级  (/etc/zshenv，需管理员)").tag(false)
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
            }

            if let e = errorText {
                Text(e).font(.caption).foregroundColor(Theme.danger)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(EnvButtonStyle(kind: .bordered))
                Button("保存") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(EnvButtonStyle(kind: .primary))
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, isValidIdentifier(n) else {
            errorText = "变量名只能包含字母、数字、下划线，且不能以数字开头。"
            return
        }
        vm.add(name: n, value: value, user: userScope)
        dismiss()
    }

    private func isValidIdentifier(_ s: String) -> Bool {
        guard let first = s.first, first.isLetter || first == "_" else { return false }
        return s.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}

/// 编辑值弹窗。
struct EditValueSheet: View {
    @EnvironmentObject var vm: EnvManagerViewModel
    @Environment(\.dismiss) private var dismiss

    let variable: EnvironmentVariable
    @State private var value: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("编辑 \(variable.name)")
                .font(.title2.weight(.semibold))
            Text(variable.source)
                .font(.caption).foregroundColor(Theme.secondaryText)
                .lineLimit(1).truncationMode(.middle)

            TextField("值", text: $value)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .uniformInput()

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(EnvButtonStyle(kind: .bordered))
                Button("保存") {
                    vm.update(variable, value: value)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(EnvButtonStyle(kind: .primary))
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear { value = variable.rawValue }
    }
}
