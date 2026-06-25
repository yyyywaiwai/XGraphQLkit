import Foundation

enum XGraphQLValidationRecovery {
    enum MissingKind {
        case features
        case fieldToggles

        var needle: String {
            switch self {
            case .features: return "features cannot be null:"
            case .fieldToggles: return "fieldToggles cannot be null:"
            }
        }
    }

    static func isRetryableStatus(_ status: Int) -> Bool {
        status == 400 || status == 422
    }

    static func missingKeys(from body: String, kind: MissingKind) -> [String] {
        // examples:
        // "The following features cannot be null: rweb_video_screen_enabled"
        // "The following features cannot be null: a, b, c"
        let lower = body.lowercased()
        guard let startRange = lower.range(of: kind.needle.lowercased()) else { return [] }
        let offset = lower.distance(from: lower.startIndex, to: startRange.upperBound)
        guard let bodyNeedleEnd = body.index(body.startIndex, offsetBy: offset, limitedBy: body.endIndex) else {
            return []
        }

        let afterNeedle = body[bodyNeedleEnd...]
        // stop at the next quote if present
        let segment: Substring
        if let quote = afterNeedle.firstIndex(of: "\"") {
            segment = afterNeedle[..<quote]
        } else if let brace = afterNeedle.firstIndex(of: "}") {
            segment = afterNeedle[..<brace]
        } else {
            segment = afterNeedle
        }

        let raw = segment
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\t", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if raw.isEmpty { return [] }

        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
            .filter { !$0.isEmpty }
    }
}
