import Foundation
import Combine

/// 文件级快照撤销/重做管理器。
///
/// 每个「事务」由一次用户操作触发，可能涉及多个文件的修改；撤销时按逆序把
/// 每个文件写回其「修改前」内容，重做则写回「修改后」内容。真正的写文件动作
/// 由外部注入的 `applier` 完成（内含管理员授权回退）。
final class FileSnapshotUndoManager: ObservableObject {

    struct Change {
        let path: String
        let before: String
        let after: String
    }

    struct Transaction: Identifiable {
        let id = UUID()
        let label: String
        var changes: [Change] = []
    }

    /// 写文件回调：(path, content)。
    typealias Applier = (String, String) throws -> Void

    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false
    @Published private(set) var undoCount = 0

    private let applier: Applier
    private var undoStack: [Transaction] = []
    private var redoStack: [Transaction] = []
    private var current: Transaction?

    private static let maxHistory = 50

    init(applier: @escaping Applier) {
        self.applier = applier
    }

    // MARK: - 事务

    /// 当前是否处于某个事务中（用于支持嵌套调用不重复开启）。
    var isInTransaction: Bool { current != nil }

    /// 开启事务；若已在事务中则保持当前事务不变（嵌套复用）。
    /// 返回是否由本次调用真正开启（用于决定是否 commit）。
    @discardableResult
    func begin(_ label: String) -> Bool {
        if current != nil { return false }
        current = Transaction(label: label)
        return true
    }

    func record(path: String, before: String, after: String) {
        current?.changes.append(Change(path: path, before: before, after: after))
    }

    func commit() {
        if let t = current, !t.changes.isEmpty {
            undoStack.append(t)
            if undoStack.count > Self.maxHistory { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        current = nil
        refresh()
    }

    func cancel() { current = nil }

    // MARK: - 撤销 / 重做

    func undo() throws {
        guard let t = undoStack.popLast() else { return }
        for c in t.changes.reversed() {
            try applier(c.path, c.before)
        }
        redoStack.append(t)
        refresh()
    }

    func redo() throws {
        guard let t = redoStack.popLast() else { return }
        for c in t.changes {
            try applier(c.path, c.after)
        }
        undoStack.append(t)
        refresh()
    }

    private func refresh() {
        canUndo = !undoStack.isEmpty
        canRedo = !redoStack.isEmpty
        undoCount = undoStack.count
    }
}
