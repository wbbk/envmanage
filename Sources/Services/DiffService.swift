import Foundation

/// 一行 diff 记录（F02-07 变化预览）。
struct DiffLine {
    enum Kind { case context, added, removed }
    let kind: Kind
    let text: String
}

/// 轻量行级 diff：先剥离公共前后缀，再对中间段做 LCS。
/// 配置文件体量小（数百行内），该复杂度足够，且零依赖。
enum DiffService {

    static func diff(before: String, after: String) -> [DiffLine] {
        let a = before.components(separatedBy: .newlines)
        let b = after.components(separatedBy: .newlines)

        // 公共前缀
        var head = 0
        while head < a.count, head < b.count, a[head] == b[head] { head += 1 }
        // 公共后缀（不越过前缀）
        var tail = 0
        while tail < a.count - head, tail < b.count - head,
              a[a.count - 1 - tail] == b[b.count - 1 - tail] { tail += 1 }

        let midA = Array(a[head..<a.count - tail])
        let midB = Array(b[head..<b.count - tail])

        var lines: [DiffLine] = []
        // 上下文各保留最多 2 行
        let ctxLead = min(head, 2)
        for i in stride(from: head - ctxLead, to: head, by: 1) {
            lines.append(DiffLine(kind: .context, text: a[i]))
        }
        if head - ctxLead > 0 {
            lines.append(DiffLine(kind: .context, text: "… 上略 \(head - ctxLead) 行 …"))
        }

        // 中间段 LCS
        let n = midA.count, m = midB.count
        if n * m <= 400_000 {
            var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    dp[i][j] = midA[i] == midB[j]
                        ? dp[i + 1][j + 1] + 1
                        : max(dp[i + 1][j], dp[i][j + 1])
                }
            }
            var i = 0, j = 0
            while i < n, j < m {
                if midA[i] == midB[j] {
                    lines.append(DiffLine(kind: .context, text: midA[i])); i += 1; j += 1
                } else if dp[i + 1][j] >= dp[i][j + 1] {
                    lines.append(DiffLine(kind: .removed, text: midA[i])); i += 1
                } else {
                    lines.append(DiffLine(kind: .added, text: midB[j])); j += 1
                }
            }
            while i < n { lines.append(DiffLine(kind: .removed, text: midA[i])); i += 1 }
            while j < m { lines.append(DiffLine(kind: .added, text: midB[j])); j += 1 }
        } else {
            // 超大变更兜底：整段替换
            for s in midA { lines.append(DiffLine(kind: .removed, text: s)) }
            for s in midB { lines.append(DiffLine(kind: .added, text: s)) }
        }

        let ctxTail = min(tail, 2)
        if tail - ctxTail > 0 {
            lines.append(DiffLine(kind: .context, text: "… 后略 \(tail - ctxTail) 行 …"))
        }
        for i in stride(from: a.count - tail, to: a.count - tail + ctxTail, by: 1) {
            lines.append(DiffLine(kind: .context, text: a[i]))
        }
        return lines
    }

    /// 渲染为带 +/- 前缀的纯文本（用于 NSAlert / Text 展示）。
    static func render(_ lines: [DiffLine], maxLines: Int = 120) -> String {
        var out = ""
        for l in lines.prefix(maxLines) {
            switch l.kind {
            case .context: out += "  " + l.text
            case .added:   out += "+ " + l.text
            case .removed: out += "- " + l.text
            }
            out += "\n"
        }
        if lines.count > maxLines { out += "… 共 \(lines.count) 行，余下省略 …\n" }
        return out
    }
}
