import Foundation

/// 变量值的展开预览（F02-05）：把 `~`、`$NAME`、`${NAME}` 依据运行时环境展开，
/// 仅用于「预览」，绝不回写配置——原始表达式始终保留。
enum ValueExpander {

    /// 展开一个原始值。env 缺省用当前进程环境；未知变量原样保留。
    static func expand(_ raw: String, env: [String: String] = ProcessInfo.processInfo.environment) -> String {
        var result = ""
        let chars = Array(raw)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            // 起始处的 ~ 或 ~/
            if ch == "~", i == 0, i + 1 == chars.count || chars[i + 1] == "/" {
                result += env["HOME"] ?? NSHomeDirectory()
                i += 1
                continue
            }
            if ch == "$", i + 1 < chars.count {
                // ${NAME}
                if chars[i + 1] == "{", let close = indexOf(chars, "}", from: i + 2) {
                    let name = String(chars[(i + 2)..<close])
                    result += resolve(name, env: env)
                    i = close + 1
                    continue
                }
                // $NAME
                if isIdentStart(chars[i + 1]) {
                    var j = i + 1
                    while j < chars.count, isIdentChar(chars[j]) { j += 1 }
                    let name = String(chars[(i + 1)..<j])
                    result += resolve(name, env: env)
                    i = j
                    continue
                }
            }
            result.append(ch)
            i += 1
        }
        return result
    }

    /// 提取值中引用到的变量名（用于展示依赖）。
    static func referencedNames(_ raw: String) -> [String] {
        var names: [String] = []
        let chars = Array(raw)
        var i = 0
        while i < chars.count {
            if chars[i] == "$", i + 1 < chars.count {
                if chars[i + 1] == "{", let close = indexOf(chars, "}", from: i + 2) {
                    names.append(String(chars[(i + 2)..<close]))
                    i = close + 1
                    continue
                }
                if isIdentStart(chars[i + 1]) {
                    var j = i + 1
                    while j < chars.count, isIdentChar(chars[j]) { j += 1 }
                    names.append(String(chars[(i + 1)..<j]))
                    i = j
                    continue
                }
            }
            i += 1
        }
        return Array(Set(names))
    }

    private static func resolve(_ name: String, env: [String: String]) -> String {
        if let v = env[name] { return v }
        if name == "HOME" { return NSHomeDirectory() }
        return "$\(name)"   // 未知变量保留原样，不虚构
    }

    private static func indexOf(_ chars: [Character], _ target: Character, from: Int) -> Int? {
        var i = from
        while i < chars.count { if chars[i] == target { return i }; i += 1 }
        return nil
    }

    private static func isIdentStart(_ c: Character) -> Bool { c.isLetter || c == "_" }
    private static func isIdentChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
}
