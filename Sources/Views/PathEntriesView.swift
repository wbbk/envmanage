import SwiftUI

/// 「PATH 管理」视图：受管 PATH 条目增删/排序（F04-03），
/// 并按顺序展示运行时生效的 PATH 目录，校验存在性并标注来源。
struct PathEntriesView: View {
    @EnvironmentObject var vm: EnvManagerViewModel
    @State private var newDir: String = ""

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(spacing: 6) {
                    // 受管 PATH 条目（F04-03）
                    managedCard
                        .padding(.bottom, 10)
                    // 命令查找器（F04-06）
                    CommandFinderView()
                        .padding(.bottom, 8)
                    Text("PATH 目录（按生效顺序）")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(Theme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 2)
                    ForEach(vm.pathEntries) { entry in
                        row(entry)
                    }
                }
                .padding(12)
            }
            .background(Theme.windowBG)
        }
    }

    private var dupDirs: [String] {
        vm.duplicates.first(where: { $0.kind == .pathDir })?.detail
            .components(separatedBy: "  ;  ") ?? []
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("PATH 目录（运行时生效顺序）").font(.headline)
                Text("共 \(vm.pathEntries.count) 项，越靠上优先级越高。")
                    .font(.caption).foregroundColor(Theme.secondaryText)
            }
            Spacer()
            if !dupDirs.isEmpty {
                Label("发现 \(dupDirs.count) 个重复目录", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(Theme.warning)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .frame(height: Theme.badgeH)                   // 统一标签高度
                    .background(Theme.warning.opacity(0.12))
                    .cornerRadius(Theme.controlCorner)
            }
        }
        .padding(.horizontal, Theme.hpad)
        .padding(.vertical, 12)
    }

    private func row(_ entry: PathEntry) -> some View {
        HStack(spacing: 10) {
            Text("\(entry.order)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 26, height: Theme.badgeH)
                .background(Theme.secondaryText.opacity(0.7))
                .cornerRadius(5)

            Image(systemName: entry.exists ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(entry.exists ? Theme.success : Theme.danger)

            Text(entry.directory)
                .font(.system(.callout, design: .monospaced))
                .foregroundColor(entry.exists ? Theme.primaryText : Theme.secondaryText)
                .lineLimit(1).truncationMode(.middle)

            Spacer()

            if dupDirs.contains(entry.directory) {
                Text("重复").font(.caption2).foregroundColor(Theme.warning)
                    .uniformTag()
                    .background(Theme.warning.opacity(0.15)).cornerRadius(5)
            }
            if !entry.exists {
                Text("缺失").font(.caption2).foregroundColor(Theme.danger)
                    .uniformTag()
                    .background(Theme.danger.opacity(0.12)).cornerRadius(5)
            }
            ScopeBadge(scope: entry.scope)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Theme.cardBG)
        .cornerRadius(8)
    }

    // MARK: - 受管 PATH 条目（F04-03）

    private var managedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.right.square").foregroundColor(Theme.accent)
                Text("受管 PATH 条目").font(.headline).foregroundColor(Theme.primaryText)
                Text("写入 ~/.zshrc 受管区块 · 越靠上优先级越高")
                    .font(.caption).foregroundColor(Theme.secondaryText)
                    .lineLimit(1).truncationMode(.tail)
                Spacer()
                if !vm.managedPathEntries.isEmpty {
                    Button(action: { vm.requestManagedPath([]) }) {
                        Label("清空区块", systemImage: "trash")
                    }
                    .buttonStyle(EnvButtonStyle(kind: .bordered, color: Theme.danger))
                    .fixedSize()
                }
            }

            if vm.managedPathEntries.isEmpty {
                Text("尚无受管条目。添加后，新开终端时这些目录会排在现有 PATH 之前。")
                    .font(.caption).foregroundColor(Theme.secondaryText)
            } else {
                ForEach(Array(vm.managedPathEntries.enumerated()), id: \.offset) { idx, dir in
                    HStack(spacing: 8) {
                        Text("\(idx + 1)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 26, height: Theme.badgeH)
                            .background(Theme.accent.opacity(0.8))
                            .cornerRadius(5)
                        Text(dir)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundColor(Theme.primaryText)
                            .lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button(action: { move(idx, up: true) }) {
                            Image(systemName: "chevron.up").font(.system(size: 11))
                        }
                        .buttonStyle(EnvButtonStyle(kind: .icon(Theme.primaryText), hpad: 8))
                        .disabled(idx == 0)
                        Button(action: { move(idx, up: false) }) {
                            Image(systemName: "chevron.down").font(.system(size: 11))
                        }
                        .buttonStyle(EnvButtonStyle(kind: .icon(Theme.primaryText), hpad: 8))
                        .disabled(idx == vm.managedPathEntries.count - 1)
                        Button(action: {
                            var list = vm.managedPathEntries
                            list.remove(at: idx)
                            vm.requestManagedPath(list)
                        }) {
                            Image(systemName: "xmark").font(.system(size: 11))
                        }
                        .buttonStyle(EnvButtonStyle(kind: .icon(Theme.danger), hpad: 8))
                    }
                    .padding(.vertical, 3)
                }
            }

            HStack(spacing: 8) {
                TextField("新目录，如 ~/tools/bin 或 /usr/local/opt/x/bin", text: $newDir)
                    .textFieldStyle(.plain)
                    .uniformInput()
                    .onSubmit(addDir)
                Button(action: addDir) {
                    Label("添加", systemImage: "plus")
                }
                .buttonStyle(EnvButtonStyle(kind: .primary))
                .fixedSize()
                .disabled(newDir.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Text("提示：支持 ~ 前缀；排序与增删都会先展示变更预览，确认后才写入。")
                .font(.caption2).foregroundColor(Theme.secondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBG)
        .cornerRadius(Theme.corner)
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.separator, lineWidth: 1))
    }

    private func addDir() {
        let dir = newDir.trimmingCharacters(in: .whitespaces)
        guard !dir.isEmpty else { return }
        var list = vm.managedPathEntries
        list.removeAll { $0 == dir }
        list.insert(dir, at: 0)   // 新目录排在最前（优先级最高）
        newDir = ""
        vm.requestManagedPath(list)
    }

    private func move(_ idx: Int, up: Bool) {
        var list = vm.managedPathEntries
        let target = up ? idx - 1 : idx + 1
        guard target >= 0, target < list.count else { return }
        list.swapAt(idx, target)
        vm.requestManagedPath(list)
    }
}
