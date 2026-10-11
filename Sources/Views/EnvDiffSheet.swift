import SwiftUI
import AppKit

/// GUI 与 Shell 环境差异诊断的结果弹窗（F10-02）：
/// 设置页行内展示会截断长值看不清，这里提供可搜索、可按类别过滤、
/// 完整换行展示两侧值并支持逐项复制的宽弹窗。
struct EnvDiffSheet: View {
    let rows: [EnvDiffRow]
    var onDismiss: () -> Void

    @State private var filterKind: EnvDiffRow.Kind? = nil
    @State private var search = ""
    @State private var copiedID: String? = nil

    private var filtered: [EnvDiffRow] {
        rows.filter { row in
            (filterKind == nil || row.kind == filterKind)
                && (search.isEmpty
                    || row.name.localizedCaseInsensitiveContains(search)
                    || (row.shellValue ?? "").localizedCaseInsensitiveContains(search)
                    || (row.guiValue ?? "").localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            controls
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 780, height: 560)
        .background(Theme.windowBG)
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 8) {
            Label("GUI 与 Shell 环境差异", systemImage: "stethoscope")
                .font(.headline).foregroundColor(Theme.primaryText)
            Text("共 \(rows.count) 项")
                .font(.caption).foregroundColor(Theme.secondaryText)
                .uniformTag()
                .background(Theme.subtleBG).cornerRadius(5)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill").font(.system(size: 15))
                    .foregroundColor(Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .help("关闭")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(Theme.cardBG)
    }

    // MARK: - 过滤与搜索

    private var controls: some View {
        HStack(spacing: 10) {
            SegmentedToggle(
                options: [("全部", Optional<EnvDiffRow.Kind>.none),
                          ("仅 Shell 有", EnvDiffRow.Kind.onlyInShell),
                          ("仅 GUI 有", EnvDiffRow.Kind.onlyInGUI),
                          ("值不同", EnvDiffRow.Kind.valueDiff)],
                selection: $filterKind)
            TextField("搜索变量名或值…", text: $search)
                .textFieldStyle(.plain).uniformInput()
                .frame(maxWidth: 240)
            Spacer()
            Text("终端有而 GUI 没有，通常解释「双击打开的 App 找不到命令」")
                .font(.caption2).foregroundColor(Theme.secondaryText)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.cardBG)
    }

    // MARK: - 列表

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if filtered.isEmpty {
                    Text(rows.isEmpty
                         ? "诊断完成：GUI 与 Shell 环境无异常差异。"
                         : "当前过滤条件下没有匹配项。")
                        .font(.caption).foregroundColor(Theme.secondaryText)
                        .padding(.top, 30)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                ForEach(filtered) { row in
                    rowCard(row)
                }
            }
            .padding(14)
        }
        .background(Theme.windowBG)
    }

    private func rowCard(_ row: EnvDiffRow) -> some View {
        let color = kindColor(row.kind)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(row.kind.rawValue)
                    .font(.caption2).foregroundColor(color)
                    .uniformTag()
                    .background(color.opacity(0.12))
                    .cornerRadius(5)
                    .fixedSize()
                Text(row.name)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
            }
            if let sv = row.shellValue {
                valueLine(tag: "shell", value: sv, id: row.name + "#shell", color: color)
            }
            if let gv = row.guiValue {
                valueLine(tag: "gui  ", value: gv, id: row.name + "#gui", color: color)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBG)
        .cornerRadius(7)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.separator, lineWidth: 1))
    }

    /// 完整值行：不截断、允许换行，行尾复制按钮写 NSPasteboard
    /// （不用 textSelection——它会导致 Text 不截断而溢出遮挡）。
    private func valueLine(tag: String, value: String, id: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(tag)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(Theme.secondaryText)
                .frame(width: 36, alignment: .leading)
            Text(value.isEmpty ? "（空）" : value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(value.isEmpty ? Theme.secondaryText : Theme.primaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: { copy(value, id: id) }) {
                Image(systemName: copiedID == id ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10))
            }
            .buttonStyle(EnvButtonStyle(kind: .icon(color), hpad: 7))
            .fixedSize()
            .help("复制值")
        }
    }

    private func copy(_ value: String, id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedID = id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedID == id { copiedID = nil }
        }
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 10) {
            Text("噪音变量（TERM/PWD/SHLVL/TMPDIR 等每次登录必然不同项）已排除")
                .font(.caption2).foregroundColor(Theme.secondaryText)
            Spacer()
            Text("显示 \(filtered.count) / \(rows.count) 项")
                .font(.caption).foregroundColor(Theme.secondaryText).fixedSize()
            Button(action: onDismiss) {
                Text("关闭").frame(minWidth: 56)
            }
            .buttonStyle(EnvButtonStyle(kind: .primary)).fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Theme.cardBG)
    }

    private func kindColor(_ k: EnvDiffRow.Kind) -> Color {
        switch k {
        case .onlyInShell: return Theme.warning
        case .onlyInGUI:   return Theme.accent
        case .valueDiff:   return Theme.danger
        }
    }
}
