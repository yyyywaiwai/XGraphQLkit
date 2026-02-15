import Foundation

// `main.*.js` から persisted query の operationName -> queryId を抽出する。
// 別経路へのフォールバックはせず、単一の抽出ロジックを少し広めにして追従性を上げる。
enum XOperationIDExtractor {
    static func extractOperationIDs(from mainScriptBody: String) -> [String: String] {
        // main.js では `queryId:\"...\",operationName:\"...\"` のようなエスケープ付きと、
        // `queryId:"...",operationName:"..."` のような素の形が混在し得る。
        // どちらも 1 つの正規表現で拾う。
        let pattern = #"""
        (?:
          queryid\s*:\s*(?:\\\"|\")([A-Za-z0-9_-]{8,128})(?:\\\"|\")\s*,?\s*
          operationname\s*:\s*(?:\\\"|\")([A-Za-z0-9_]{2,64})(?:\\\"|\")
        |
          operationname\s*:\s*(?:\\\"|\")([A-Za-z0-9_]{2,64})(?:\\\"|\")\s*,?\s*
          queryid\s*:\s*(?:\\\"|\")([A-Za-z0-9_-]{8,128})(?:\\\"|\")
        )
        """#

        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators, .allowCommentsAndWhitespace]
        ) else {
            return [:]
        }

        let ns = mainScriptBody as NSString
        let range = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: mainScriptBody, options: [], range: range)
        if matches.isEmpty { return [:] }

        var out: [String: String] = [:]
        out.reserveCapacity(min(matches.count, 64))

        for m in matches {
            // alt1: (1=queryId, 2=op)  alt2: (3=op, 4=queryId)
            let g1 = m.range(at: 1)
            let g2 = m.range(at: 2)
            let g3 = m.range(at: 3)
            let g4 = m.range(at: 4)

            let op: String
            let id: String

            if g1.location != NSNotFound, g2.location != NSNotFound {
                id = ns.substring(with: g1)
                op = ns.substring(with: g2)
            } else if g3.location != NSNotFound, g4.location != NSNotFound {
                op = ns.substring(with: g3)
                id = ns.substring(with: g4)
            } else {
                continue
            }

            if op.isEmpty || id.isEmpty { continue }
            out[op] = id
        }

        return out
    }
}

