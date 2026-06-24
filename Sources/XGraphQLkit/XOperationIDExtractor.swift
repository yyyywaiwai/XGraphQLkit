import Foundation

// X web JavaScript assetsから persisted query の operationName -> queryId を抽出する。
enum XOperationIDExtractor {
    static func extractOperationIDs(from scriptBody: String) -> [String: String] {
        // Legacy responsive-web assetsでは `queryId:\"...\",operationName:\"...\"` のようなエスケープ付きと、
        // `queryId:"...",operationName:"..."` のような素の形が混在し得る。
        let legacyPattern = #"""
        (?:
          queryid\s*:\s*(?:\\\"|\")([A-Za-z0-9_-]{8,128})(?:\\\"|\")\s*,?\s*
          operationname\s*:\s*(?:\\\"|\")([A-Za-z0-9_]{2,64})(?:\\\"|\")
        |
          operationname\s*:\s*(?:\\\"|\")([A-Za-z0-9_]{2,64})(?:\\\"|\")\s*,?\s*
          queryid\s*:\s*(?:\\\"|\")([A-Za-z0-9_-]{8,128})(?:\\\"|\")
        )
        """#

        let relayPattern = #"""
        params\s*:\s*\{\s*
          id\s*:\s*(?:`|\\\"|\")([A-Za-z0-9_-]{8,128})(?:`|\\\"|\")\s*,\s*
          metadata\s*:\s*\{.*?\}\s*,\s*
          name\s*:\s*(?:`|\\\"|\")([A-Za-z0-9_]{2,128})(?:`|\\\"|\")
        """#

        let ns = scriptBody as NSString
        let range = NSRange(location: 0, length: ns.length)
        var out: [String: String] = [:]

        if let regex = try? NSRegularExpression(
            pattern: legacyPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators, .allowCommentsAndWhitespace]
        ) {
            let matches = regex.matches(in: scriptBody, options: [], range: range)
            out.reserveCapacity(min(matches.count, 64))

            for match in matches {
                // alt1: (1=queryId, 2=op)  alt2: (3=op, 4=queryId)
                let g1 = match.range(at: 1)
                let g2 = match.range(at: 2)
                let g3 = match.range(at: 3)
                let g4 = match.range(at: 4)

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
        }

        if let regex = try? NSRegularExpression(
            pattern: relayPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators, .allowCommentsAndWhitespace]
        ) {
            let matches = regex.matches(in: scriptBody, options: [], range: range)
            for match in matches {
                let idRange = match.range(at: 1)
                let opRange = match.range(at: 2)
                guard idRange.location != NSNotFound, opRange.location != NSNotFound else {
                    continue
                }
                let id = ns.substring(with: idRange)
                let op = ns.substring(with: opRange)
                if op.isEmpty || id.isEmpty { continue }
                out[op] = id
            }
        }

        return out
    }
}
