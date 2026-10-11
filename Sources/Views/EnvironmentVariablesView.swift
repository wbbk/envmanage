import SwiftUI
import AppKit

/// 筛选按钮项。
struct FilterItem: Identifiable {
    let id = UUID()
    let label: String
    let scope: EnvScope?
}

/// 「环境变量」主视图：筛选 + 搜索 + 列表 + 右侧详情面板（三栏）。
struct EnvironmentVariablesView: View {
    @EnvironmentObject var vm: EnvManagerViewModel
    @State private var showAdd = false
    @State private var editing: EnvironmentVariable? = nil

    private let filters: [FilterItem] = [
        FilterItem(label: "全部", scope: nil),
        FilterItem(label: "系统级", scope: .system),
        FilterItem(label: "用户级", scope: .user),
        FilterItem(label: "运行时", scope: .runtime),
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                toolbar
                Divider()
                list
            }
            .frame(maxWidth: .infinity)
            Divider()
            VariableDetailPanel()
                .frame(width: 320)
        }
        .background(Theme.windowBG)
        .sheet(isPresented: $showAdd) {
            AddVariableSheet().environmentObject(vm)
        }
        .sheet(item: $editing) { v in
            EditValueSheet(variable: v).environmentObject(vm)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            ForEach(filters) { item in
                Button(action: { vm.scopeFilter = item.scope }) {
                    Text(item.label)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .frame(height: Theme.controlH)              // 统一按钮高度
                        .background(vm.scopeFilter == item.scope ? Theme.accent : Color(nsColor: .controlBackgroundColor))
                        .foregroundColor(vm.scopeFilter == item.scope ? .white : Theme.primaryText)
                        .cornerRadius(Theme.controlCorner)
                        .overlay(RoundedRectangle(cornerRadius: Theme.controlCorner)
                            .stroke(vm.scopeFilter == item.scope ? Color.clear : Theme.separator,
                                    lineWidth: 1))
                }
                .buttonStyle(.plain)
                .fixedSize()                       // 筛选按钮不被挤压
            }

            Spacer(minLength: 8)

            // 视图模式：按定义 / 按名称聚合（F01-04）
            SegmentedToggle(options: [("按定义", false), ("按名称", true)],
                            selection: $vm.groupByName)
                .help("切换「每条定义一行」/「同名聚合一行」视图")

            // 敏感值显隐（F02-06）
            Button(action: { vm.revealSecrets.toggle() }) {
                Image(systemName: vm.revealSecrets ? "eye.slash" : "eye")
            }
            .buttonStyle(EnvButtonStyle(kind: .icon(vm.revealSecrets ? Theme.accent : Theme.secondaryText)))
            .help(vm.revealSecrets ? "隐藏敏感值" : "显示敏感值明文")

            // 搜索框可弹性收缩，窄窗口下不撑爆布局
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").foregroundColor(Theme.secondaryText)
                TextField("搜索变量 / 值", text: $vm.searchText)
                    .textFieldStyle(.plain)
                    .frame(minWidth: 70, idealWidth: 160, maxWidth: 180)
            }
            .uniformInput()

            Button(action: { showAdd = true }) {
                Label("新增变量", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(EnvButtonStyle(kind: .primary))
            .fixedSize()

            Button(action: { vm.refresh() }) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(EnvButtonStyle(kind: .icon(Theme.primaryText)))
            .help("刷新 (⌘R)")
        }
        .padding(.horizontal, Theme.hpad)
        .padding(.vertical, 10)
    }

    /// 依据视图模式产出的行：聚合模式下同名只显示最终生效的一条。
    private var displayRows: [EnvironmentVariable] {
        let visible = vm.visibleEntries
        guard vm.groupByName else { return visible }
        var byName: [String: [EnvironmentVariable]] = [:]
        for e in visible { byName[e.name, default: []].append(e) }
        return byName.values.map { group in
            group.sorted { $0.orderKey < $1.orderKey }.last(where: { $0.enabled })
                ?? group.max { $0.orderKey < $1.orderKey }!
        }
        .sorted { $0.name < $1.name }
    }

    private func definitionCount(_ v: EnvironmentVariable) -> Int {
        vm.definitions(named: v.name).count
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(displayRows) { v in
                    ZStack(alignment: .topTrailing) {
                        VariableRowView(
                            variable: v,
                            isDuplicate: vm.duplicateNames.contains(v.name) && v.sourceType == .export,
                            revealSecrets: vm.revealSecrets,
                            isSelected: vm.selectedID == v.id,
                            onToggle: { vm.toggle(v) },
                            onEdit: { editing = v },
                            onDelete: { confirmDelete(v) },
                            onSelect: { vm.selectedID = v.id }
                        )
                        if vm.groupByName, definitionCount(v) > 1 {
                            Text("×\(definitionCount(v))")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .uniformTag()
                                .background(Theme.accent)
                                .clipShape(Capsule())
                                .padding(4)
                                .help("该名称有 \(definitionCount(v)) 条定义，点选查看覆盖链")
                        }
                    }
                }
            }
            .padding(10)
        }
        .overlay {
            if displayRows.isEmpty {
                EmptyStateView(icon: "magnifyingglass",
                               title: "没有匹配的环境变量",
                               subtitle: "试试切换作用域筛选，或调整搜索关键词。")
            }
        }
    }

    private func confirmDelete(_ v: EnvironmentVariable) {
        let alert = NSAlert()
        alert.messageText = "删除定义？"
        alert.informativeText = "将删除 \(v.name) 在 \(shorten(v.source)):\(v.lineNo ?? 0) 的定义行。\n此操作会自动备份且可撤销（⌘Z）。"
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        if alert.runModal() == .alertFirstButtonReturn {
            vm.remove(v)
        }
    }

    private func shorten(_ s: String) -> String {
        s.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }
}
