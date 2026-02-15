import Foundation

public actor XDirectClient {
    private let auth: XAuthContext
    private let session: URLSession
    private var operationCache: [String: String] = [:]
    private var mainScriptBodyCache: String?

    public init(auth: XAuthContext, session: URLSession = .shared) {
        self.auth = auth
        self.session = session
    }

    public func listUserPosts(screenName: String, count: Int = 20, cursor: String? = nil) async throws -> XPostsPage {
        let userId = try await resolveUserID(screenName: screenName)

        var variables: [String: Any] = [
            "userId": userId,
            "count": max(1, min(count, 100)),
            "includePromotedContent": false,
            "withQuickPromoteEligibilityTweetFields": true,
            "withVoice": true
        ]
        if let cursor, !cursor.isEmpty {
            variables["cursor"] = cursor
        }

        let root = try await requestGraphQL(
            operationName: "UserTweets",
            variables: variables,
            refererPath: "/\(screenName)"
        )

        let page = parsePostsPage(root: root, fallbackScreenName: screenName)
        return page
    }

    private func resolveUserID(screenName: String) async throws -> String {
        let root = try await requestGraphQL(
            operationName: "UserByScreenName",
            variables: [
                "screen_name": screenName,
                "withGrokTranslatedBio": false
            ],
            refererPath: "/\(screenName)"
        )

        if let id = jsonValue(at: ["data", "user", "result", "rest_id"], in: root) as? String {
            return id
        }

        throw XDirectClientError.userIdNotFound(screenName)
    }

    private func requestGraphQL(
        operationName: String,
        variables: [String: Any],
        refererPath: String
    ) async throws -> Any {
        // X の内部GraphQLは、指定しないと400になる feature key が頻繁に増える。
        // エラー本文から不足キーを拾って `false` で埋めながら数回リトライして耐性を上げる。
        var extraFeatures: [String: Any] = [:]
        var extraFieldToggles: [String: Any] = [:]

        for attempt in 0..<4 {
            do {
                return try await performGraphQLRequest(
                    operationName: operationName,
                    variables: variables,
                    refererPath: refererPath,
                    extraFeatures: extraFeatures,
                    extraFieldToggles: extraFieldToggles
                )
            } catch let XDirectClientError.badStatus(status, body) {
                guard status == 400 else { throw XDirectClientError.badStatus(status: status, body: body) }

                let missingFeatures = missingKeysFromValidationError(body: body, kind: .features)
                let missingFieldToggles = missingKeysFromValidationError(body: body, kind: .fieldToggles)

                if missingFeatures.isEmpty && missingFieldToggles.isEmpty {
                    throw XDirectClientError.badStatus(status: status, body: body)
                }

                for key in missingFeatures where extraFeatures[key] == nil {
                    extraFeatures[key] = false
                }
                for key in missingFieldToggles where extraFieldToggles[key] == nil {
                    extraFieldToggles[key] = false
                }

                // 最終attemptでまだ失敗していたら、そのままエラーを返す
                if attempt == 3 {
                    throw XDirectClientError.badStatus(status: status, body: body)
                }
            }
        }

        throw XDirectClientError.invalidResponse
    }

    private func performGraphQLRequest(
        operationName: String,
        variables: [String: Any],
        refererPath: String,
        extraFeatures: [String: Any],
        extraFieldToggles: [String: Any]
    ) async throws -> Any {
        let operationId = try await operationID(for: operationName)

        var features = defaultFeatures()
        for (k, v) in extraFeatures { features[k] = v }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "x.com"
        components.path = "/i/api/graphql/\(operationId)/\(operationName)"

        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "variables", value: jsonString(variables)))
        queryItems.append(URLQueryItem(name: "features", value: jsonString(features)))

        var fieldToggles = defaultFieldToggles(for: operationName) ?? [:]
        for (k, v) in extraFieldToggles { fieldToggles[k] = v }
        if !fieldToggles.isEmpty {
            queryItems.append(URLQueryItem(name: "fieldToggles", value: jsonString(fieldToggles)))
        }

        components.queryItems = queryItems

        guard let url = components.url else {
            throw XDirectClientError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(auth.bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue(auth.csrfToken, forHTTPHeaderField: "x-csrf-token")
        request.setValue("yes", forHTTPHeaderField: "x-twitter-active-user")
        request.setValue(auth.language, forHTTPHeaderField: "x-twitter-client-language")
        request.setValue(auth.cookieHeader, forHTTPHeaderField: "Cookie")
        request.setValue("https://x.com\(refererPath)", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw XDirectClientError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            if http.statusCode == 401 || http.statusCode == 403 {
                throw XDirectClientError.unauthorized(status: http.statusCode)
            }
            // 400 は不足features/fieldTogglesの抽出に本文が必要なので少し長めに保持する
            let limit = (http.statusCode == 400) ? 10_000 : 350
            throw XDirectClientError.badStatus(status: http.statusCode, body: String(body.prefix(limit)))
        }

        return try JSONSerialization.jsonObject(with: data, options: [])
    }

    private enum ValidationMissingKind {
        case features
        case fieldToggles

        var needle: String {
            switch self {
            case .features: return "features cannot be null:"
            case .fieldToggles: return "fieldToggles cannot be null:"
            }
        }
    }

    private func missingKeysFromValidationError(body: String, kind: ValidationMissingKind) -> [String] {
        // examples:
        // "The following features cannot be null: rweb_video_screen_enabled"
        // "The following features cannot be null: a, b, c"
        let lower = body.lowercased()
        guard let startRange = lower.range(of: kind.needle) else { return [] }
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

    private func defaultFieldToggles(for operationName: String) -> [String: Any]? {
        // 実際のWebクライアントが付けている値に寄せる（必須になることがある）
        switch operationName {
        case "UserByScreenName":
            return [
                "withPayments": false,
                "withAuxiliaryUserLabels": true
            ]
        case "UserTweets":
            return [
                "withArticlePlainText": false
            ]
        default:
            return nil
        }
    }

    private func defaultFeatures() -> [String: Any] {
        // 2026-02-16 時点でのWebクライアント相当（未指定だと 400 で落ちることがある）
        // 値は「とりあえず動く」こと優先で、将来はmain.jsなどから動的に追従させる余地あり。
        return [
            "hidden_profile_subscriptions_enabled": true,
            "profile_label_improvements_pcf_label_in_post_enabled": true,
            "responsive_web_profile_redirect_enabled": false,
            "rweb_tipjar_consumption_enabled": false,
            "verified_phone_label_enabled": false,
            "subscriptions_verification_info_is_identity_verified_enabled": true,
            "subscriptions_verification_info_verified_since_enabled": true,
            "subscriptions_feature_can_gift_premium": true,
            "highlights_tweets_tab_ui_enabled": true,
            "creator_subscriptions_tweet_preview_api_enabled": true,
            "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
            "responsive_web_graphql_timeline_navigation_enabled": true,
            "premium_content_api_read_enabled": false,
            "communities_web_enable_tweet_community_results_fetch": true,
            "c9s_tweet_anatomy_moderator_badge_enabled": true,
            "responsive_web_grok_analyze_button_fetch_trends_enabled": false,
            "responsive_web_grok_analyze_post_followups_enabled": true,
            "responsive_web_jetfuel_frame": true,
            "responsive_web_grok_share_attachment_enabled": true,
            "responsive_web_grok_annotations_enabled": true,
            "articles_preview_enabled": true,
            "responsive_web_edit_tweet_api_enabled": true,
            "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
            "view_counts_everywhere_api_enabled": true,
            "longform_notetweets_consumption_enabled": true,
            "responsive_web_twitter_article_tweet_consumption_enabled": true,
            "tweet_awards_web_tipping_enabled": false,
            "responsive_web_grok_show_grok_translated_post": false,
            "responsive_web_grok_analysis_button_from_backend": true,
            "post_ctas_fetch_enabled": false,
            "freedom_of_speech_not_reach_fetch_enabled": true,
            "standardized_nudges_misinfo": true,
            "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
            "longform_notetweets_rich_text_read_enabled": true,
            "longform_notetweets_inline_media_enabled": true,
            "responsive_web_grok_image_annotation_enabled": true,
            "responsive_web_grok_imagine_annotation_enabled": true,
            "responsive_web_grok_community_note_auto_translation_is_enabled": false,
            "responsive_web_enhance_cards_enabled": false
        ]
    }

    private func operationID(for operationName: String) async throws -> String {
        if let cached = operationCache[operationName] {
            return cached
        }

        let scriptBody = try await mainScriptBody()
        let escapedName = NSRegularExpression.escapedPattern(for: operationName)
        // NOTE: X の main.*.js は巨大な1行JSになることが多いので、strict→loose の順で探す
        let strict = "queryId:\\\"([^\\\"]+)\\\"\\s*,\\s*operationName:\\\"\\(escapedName)\\\""
            .replacingOccurrences(of: "\\(escapedName)", with: escapedName)
        let loose = "queryId:\\\"([^\\\"]+)\\\".*?operationName:\\\"\\(escapedName)\\\""
            .replacingOccurrences(of: "\\(escapedName)", with: escapedName)

        let queryId = firstCaptureGroup(in: scriptBody, pattern: strict)
            ?? firstCaptureGroup(in: scriptBody, pattern: loose, regexOptions: [.dotMatchesLineSeparators])

        guard let queryId else {
            throw XDirectClientError.operationNotFound(operationName)
        }

        operationCache[operationName] = queryId
        return queryId
    }

    private func mainScriptBody() async throws -> String {
        if let cached = mainScriptBodyCache {
            return cached
        }

        let scriptURL = try await XAuthCapture.findMainScriptURL(session: session)
        let (data, response) = try await session.data(from: scriptURL)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw XDirectClientError.invalidResponse
        }
        let body = String(data: data, encoding: .utf8) ?? ""
        mainScriptBodyCache = body
        return body
    }

    private func parsePostsPage(root: Any, fallbackScreenName: String) -> XPostsPage {
        var tweetResults: [[String: Any]] = []
        collectTweetResults(in: root, into: &tweetResults)

        var seenIDs = Set<String>()
        var posts: [XPost] = []

        for result in tweetResults {
            guard let post = toPost(from: result, fallbackScreenName: fallbackScreenName) else { continue }
            if seenIDs.contains(post.id) { continue }
            seenIDs.insert(post.id)
            posts.append(post)
        }

        let nextCursor = findBottomCursor(in: root)
        return XPostsPage(posts: posts, nextCursor: nextCursor)
    }

    private func toPost(from result: [String: Any], fallbackScreenName: String) -> XPost? {
        guard let restID = result["rest_id"] as? String,
              let legacy = result["legacy"] as? [String: Any] else {
            return nil
        }

        let text = (legacy["full_text"] as? String) ?? (legacy["text"] as? String) ?? ""
        guard !text.isEmpty else { return nil }

        let createdAtRaw = legacy["created_at"] as? String
        let createdAt = createdAtRaw.flatMap(parseTwitterDate)
        let screenName = extractScreenName(from: result) ?? fallbackScreenName
        let media = extractMedia(from: legacy, postID: restID)

        guard let url = URL(string: "https://x.com/\(screenName)/status/\(restID)") else {
            return nil
        }

        return XPost(
            id: restID,
            text: text,
            screenName: screenName,
            createdAt: createdAt,
            createdAtRaw: createdAtRaw,
            url: url,
            media: media
        )
    }

    private func extractMedia(from legacy: [String: Any], postID: String) -> [XMediaItem] {
        // 画像/動画は legacy.extended_entities.media が一番揃っていることが多い
        let containers: [[String: Any]] = [
            (legacy["extended_entities"] as? [String: Any])?["media"] as? [[String: Any]] ?? [],
            (legacy["entities"] as? [String: Any])?["media"] as? [[String: Any]] ?? []
        ].flatMap { $0 }

        if containers.isEmpty { return [] }

        var out: [XMediaItem] = []
        out.reserveCapacity(containers.count)

        for (idx, media) in containers.enumerated() {
            guard let typeRaw = media["type"] as? String else { continue }
            let kind = XMediaKind(rawValue: typeRaw) ?? (typeRaw == "gif" ? .animatedGif : nil)

            let id = (media["media_key"] as? String) ?? "\(postID)-\(idx)"
            let thumbURL = (media["media_url_https"] as? String).flatMap(URL.init(string:))
                ?? (media["media_url"] as? String).flatMap(URL.init(string:))

            if kind == .photo {
                let photoURLString = (media["media_url_https"] as? String) ?? (media["media_url"] as? String)
                guard let photoURLString, let url = URL(string: photoURLString) else { continue }

                let aspect = aspectRatioFrom(media: media)
                out.append(XMediaItem(id: id, kind: .photo, url: url, thumbnailURL: nil, aspectRatio: aspect))
                continue
            }

            // video / animated_gif
            if let playback = pickPlaybackURL(from: media) {
                let aspect = aspectRatioFrom(media: media)
                out.append(XMediaItem(id: id, kind: (kind ?? .video), url: playback, thumbnailURL: thumbURL, aspectRatio: aspect))
            }
        }

        // 同じURLが複数経路で混ざることがあるので軽くdedupe
        var seen = Set<String>()
        return out.filter { item in
            let key = "\(item.kind.rawValue)|\(item.url.absoluteString)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func pickPlaybackURL(from media: [String: Any]) -> URL? {
        guard let videoInfo = media["video_info"] as? [String: Any],
              let variants = videoInfo["variants"] as? [[String: Any]] else { return nil }

        // まずHLS(m3u8)を優先。なければ mp4 の最大bitrate。
        if let hls = variants.first(where: { ($0["content_type"] as? String)?.contains("mpegurl") == true }),
           let urlStr = hls["url"] as? String,
           let url = URL(string: urlStr) {
            return url
        }

        var best: (url: URL, bitrate: Int)?
        for v in variants {
            guard let ct = v["content_type"] as? String, ct == "video/mp4",
                  let urlStr = v["url"] as? String,
                  let url = URL(string: urlStr) else { continue }
            let br = v["bitrate"] as? Int ?? 0
            if let current = best {
                if br > current.bitrate { best = (url, br) }
            } else {
                best = (url, br)
            }
        }
        return best?.url
    }

    private func aspectRatioFrom(media: [String: Any]) -> Double? {
        if let videoInfo = media["video_info"] as? [String: Any],
           let ar = videoInfo["aspect_ratio"] as? [Any],
           ar.count == 2,
           let w = ar[0] as? Int,
           let h = ar[1] as? Int,
           h != 0 {
            return Double(w) / Double(h)
        }

        if let original = media["original_info"] as? [String: Any],
           let w = original["width"] as? Int,
           let h = original["height"] as? Int,
           h != 0 {
            return Double(w) / Double(h)
        }

        return nil
    }

    private func extractScreenName(from result: [String: Any]) -> String? {
        guard let core = result["core"] as? [String: Any],
              let userResults = core["user_results"] as? [String: Any],
              let userResult = userResults["result"] as? [String: Any],
              let legacy = userResult["legacy"] as? [String: Any] else {
            return nil
        }
        return legacy["screen_name"] as? String
    }

    private func collectTweetResults(in node: Any, into sink: inout [[String: Any]]) {
        if let dict = node as? [String: Any] {
            if let tweetResults = dict["tweet_results"] as? [String: Any],
               let result = tweetResults["result"] as? [String: Any] {
                sink.append(result)
            }

            if let tweetResult = dict["tweetResult"] as? [String: Any],
               let result = tweetResult["result"] as? [String: Any] {
                sink.append(result)
            }

            for value in dict.values {
                collectTweetResults(in: value, into: &sink)
            }
        } else if let array = node as? [Any] {
            for value in array {
                collectTweetResults(in: value, into: &sink)
            }
        }
    }

    private func findBottomCursor(in node: Any) -> String? {
        if let dict = node as? [String: Any] {
            if (dict["cursorType"] as? String) == "Bottom",
               let value = dict["value"] as? String,
               !value.isEmpty {
                return value
            }
            for value in dict.values {
                if let found = findBottomCursor(in: value) {
                    return found
                }
            }
        } else if let array = node as? [Any] {
            for value in array {
                if let found = findBottomCursor(in: value) {
                    return found
                }
            }
        }

        return nil
    }

    private func jsonValue(at path: [String], in root: Any) -> Any? {
        var current: Any? = root
        for key in path {
            guard let dict = current as? [String: Any] else { return nil }
            current = dict[key]
        }
        return current
    }

    private func jsonString(_ dictionary: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dictionary, options: []),
              let text = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return text
    }

    private func firstCaptureGroup(
        in text: String,
        pattern: String,
        regexOptions: NSRegularExpression.Options = []
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: regexOptions) else { return nil }
        let ns = text as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1 else { return nil }

        return ns.substring(with: match.range(at: 1))
    }

    private func parseTwitterDate(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE MMM dd HH:mm:ss Z yyyy"
        return formatter.date(from: raw)
    }
}
