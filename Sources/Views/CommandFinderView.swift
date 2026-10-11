import SwiftUI

/// 命令查找器（F04-06）：输入命令名，列出其在生效 PATH 上的全部命中、
/// 第一命中、符号链接解析链与被遮蔽项，回答「为什么执行的不是这个」。
struct CommandFinderView: View {
    @EnvironmentObject var vm: EnvManagerViewModel

    private let suggestions = ["python3", "python", "pip3", "pip", "node", "npm", "java", "go", "git", "brew"]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass.circle.fill")
                    .foregroundColor(Theme.accent)
                TextField("输入命令名，如 python3", text: $vm.finderCommand)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { vm.runCommandFinder() }
                    .frame(minWidth: 120, maxWidth: 220)
                    .uniformInput()
                Button("查找") { vm.runCommandFinder() }
                    .buttonStyle(EnvButtonStyle(kind: .primary))
                Spacer()
            }

            // 快捷建议
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("常见：").font(.caption).foregroundColor(Theme.secondaryText)
                    ForEach(suggestions, id: \.self) { s in
                        Button(s) { vm.finderCommand = s; vm.runCommandFinder() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(Theme.primaryText)
                            .padding(.horizontal, 8)
                            .frame(height: Theme.controlH)          // 统一按钮高度
                            .background(Theme.cardBG)
                            .cornerRadius(Theme.controlCorner)
                            .overlay(RoundedRectangle(cornerRadius: Theme.controlCorner)
                                .stroke(Theme.separator, lineWidth: 1))
                    }
                }
                .fixedSize()
            }

            if let r = vm.finderResult {
                result(r)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.subtleBG)
        .cornerRadius(Theme.corner)
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.separator, lineWidth: 1))
    }

    @ViewBuilder
    private func result(_ r: CommandResolution) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            if r.hits.isEmpty {
                Label("在生效 PATH 中未找到可执行的 \(r.command)", systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(Theme.danger).font(.callout)
            } else {
                // 概览
                HStack(spacing: 8) {
                    Text("\(r.command)").font(.system(.body, design: .monospaced).weight(.bold))
                    Text("命中 \(r.hits.count) 处").font(.caption).foregroundColor(Theme.secondaryText)
                    if r.hasShadowing {
                        Label("存在遮蔽：更高优先级的命中会覆盖其余", systemImage: "square.3.layers.3d.down.right")
                            .font(.caption).foregroundColor(Theme.warning)
                    }
                    Spacer()
                }
                .foregroundColor(Theme.primaryText)

                ForEach(r.hits) { hit in hitRow(hit, first: hit.id == r.firstHit?.id) }
            }
        }
    }

    private func hitRow(_ hit: CommandHit, first: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Image(systemName: first ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(first ? Theme.success : Theme.secondaryText.opacity(0.5))
                Text(hit.path)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundColor(Theme.primaryText)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("#\(hit.order)").font(.caption).foregroundColor(Theme.secondaryText)
                    .fixedSize().layoutPriority(1)
                if first {
                    Text("实际执行").font(.caption2.weight(.semibold)).foregroundColor(.white)
                        .uniformTag()
                        .background(Theme.success).cornerRadius(5)
                } else {
                    Text("被遮蔽").font(.caption2).foregroundColor(Theme.warning)
                        .uniformTag()
                        .background(Theme.warning.opacity(0.15)).cornerRadius(5)
                }
            }
            if hit.isSymlink {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 9))
                    Text("符号链接 → \(hit.realpath)")
                        .font(.system(.caption2, design: .monospaced))
                        .lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundColor(Theme.secondaryText)
                .padding(.leading, 26)
            }
        }
        .padding(8)
        .background(first ? Theme.success.opacity(0.07) : Theme.cardBG)
        .cornerRadius(7)
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.separator, lineWidth: 1))
    }
}
