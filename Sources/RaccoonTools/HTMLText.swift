import Foundation

/// Fast single-pass HTML → plain text conversion.
///
/// The previous implementation stripped tags with `[\\s\\S]*?` regexes, which
/// is catastrophically slow on multi-megabyte modern pages (minutes of CPU —
/// the "summarize link runs forever" bug). This is a plain O(n) scan:
/// script/style blocks are skipped entirely, tags become a space, whitespace
/// runs collapse.
func stripHTML(_ html: String, cap: Int = 600_000) -> String {
    let capped = html.count > cap ? String(html.prefix(cap)) : html
    let chars = Array(capped)
    let n = chars.count
    var out: [Character] = []
    out.reserveCapacity(min(n / 4, 200_000))
    var i = 0
    var lastWasSpace = true

    func matches(_ word: String, at idx: Int) -> Bool {
        let w = Array(word)
        guard idx + w.count <= n else { return false }
        for k in 0..<w.count where String(chars[idx + k]).lowercased() != String(w[k]) {
            return false
        }
        return true
    }

    while i < n {
        let c = chars[i]
        if c == "<" {
            // script/style: skip the whole block up to its closing tag
            if matches("<script", at: i) || matches("<style", at: i) {
                let close = matches("<script", at: i) ? "</script" : "</style"
                i += 1
                while i < n, !(chars[i] == "<" && matches(close, at: i)) { i += 1 }
            }
            // skip the tag itself
            while i < n, chars[i] != ">" { i += 1 }
            i += 1
            if !lastWasSpace { out.append(" "); lastWasSpace = true }
        } else if c.isWhitespace {
            if !lastWasSpace { out.append(" "); lastWasSpace = true }
            i += 1
        } else {
            out.append(c)
            lastWasSpace = false
            i += 1
        }
    }
    return String(out).trimmingCharacters(in: .whitespaces)
}
