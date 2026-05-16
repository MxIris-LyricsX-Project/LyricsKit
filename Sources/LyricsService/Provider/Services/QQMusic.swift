import Foundation
import LyricsCore
import FoundationToolbox

private let qqSearchBaseURLString1 = "https://c.y.qq.com/splcloud/fcgi-bin/smartbox_new.fcg"
private let qqSearchBaseURLString2 = "https://u.y.qq.com/cgi-bin/musicu.fcg"
private let qqLyricsBaseURLString1 = "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg"
private let qqLyricsBaseURLString2 = "https://c.y.qq.com/qqmusic/fcgi-bin/lyric_download.fcg"

extension LyricsProviders {
    @Loggable
    final class QQMusic {
        init() {}
    }
}

extension LyricsProviders.QQMusic: _LyricsProvider {
    struct LyricsToken {
        let value: QQMusicSongSearchResult
    }

    static let service: String = "QQMusic"

    func search(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
        return try await withThrowingTaskGroup(of: [LyricsToken].self, returning: [LyricsToken].self) { group in
            group.addTask {
                return try await self.searchApi1(for: request)
            }

            group.addTask {
                return try await self.searchApi2(for: request)
            }

            var combinedResults: [LyricsToken] = []
            for try await results in group {
                combinedResults.append(contentsOf: results)
            }
            return combinedResults
        }
    }

    private func searchApi1(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
        let parameter = ["key": request.searchTerm.description]
        guard let url = URL(string: qqSearchBaseURLString1 + "?" + parameter.stringFromHttpParameters) else {
            throw LyricsProviderError.invalidURL(urlString: qqSearchBaseURLString1)
        }

        do {
            let (data, _) = try await URLSession.shared.data(for: .init(url: url))
            let result = try JSONDecoder().decode(QQResponseSearchResult.self, from: data)
            return result.data.song.list.map { LyricsToken(value: $0) }
        } catch {
            #log(.error, "QQMusic search API 1 failed: \(error)")
            return []
        }
    }

    // Search via the musicu endpoint (POST JSON).
    private func searchApi2(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
        let requestBody: [String: Any] = [
            "req_1": [
                "method": "DoSearchForQQMusicDesktop",
                "module": "music.search.SearchCgiService",
                "param": [
                    "num_per_page": 20,
                    "page_num": 1,
                    "query": request.searchTerm.description,
                    "search_type": 0, // 0 = single track
                ],
            ],
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody),
              let url = URL(string: qqSearchBaseURLString2) else {
            return []
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = bodyData
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let result = try JSONDecoder().decode(QQResponseSearchResult2.self, from: data)
            guard result.request.code == 0 else { return [] }
            return result.request.data.body.song.list.map { LyricsToken(value: $0) }
        } catch {
            #log(.error, "QQMusic search API 2 failed: \(error)")
            return []
        }
    }

    func fetch(with token: LyricsToken) async throws -> Lyrics {
        let token = token.value
        let parameter: [String: Any] = [
            "musicid": token.id,
            "version": 15,
            "miniversion": 82,
            "lrctype": 4,
        ]

        guard let url = URL(string: qqLyricsBaseURLString2) else {
            throw LyricsProviderError.invalidURL(urlString: qqLyricsBaseURLString2)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // The server checks the Referer header.
        req.setValue("https://c.y.qq.com/", forHTTPHeaderField: "Referer")
        req.httpBody = parameter.stringFromHttpParameters.data(using: .utf8)

        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(for: req)
        } catch {
            throw LyricsProviderError.networkError(underlyingError: error)
        }

        guard var dataString = String(data: data, encoding: .utf8) else {
            throw LyricsProviderError.processingFailed(reason: "Could not convert data to string.")
        }
        dataString = dataString.replacingOccurrences(of: "<!--", with: "").replacingOccurrences(of: "-->", with: "")

        guard let xmlDocument = try? XMLUtils.create(content: dataString) else {
            throw LyricsProviderError.processingFailed(reason: "Failed to parse QQMusic XML response.")
        }

        let decodedContents = decodeLyricContents(from: xmlDocument)

        guard let origContent = decodedContents["orig"] else {
            throw LyricsProviderError.processingFailed(reason: "Failed to parse or decrypt QQMusic QRC lyrics.")
        }

        let normalizedOrigContent = normalizeExtendedLrcTimestamps(origContent)
        guard let lrc = Lyrics(qqmusicQrcContent: origContent)
            ?? Lyrics(origContent)
            ?? Lyrics(normalizedOrigContent) else {
            throw LyricsProviderError.processingFailed(reason: "Failed to parse or decrypt QQMusic QRC lyrics.")
        }

        lrc.idTags[.title] = token.name
        lrc.idTags[.artist] = token.singers.joined(separator: ",")
        lrc.metadata.serviceToken = "\(token.mid)"
        lrc.metadata.artworkURL = await fetchAlbumCoverURL(songMid: token.mid)

        if let transContent = decodedContents["ts"],
           let transLrc = Lyrics(transContent) {
            lrc.merge(translation: transLrc)
        }

        return lrc
    }

    private func decodeLyricContents(from document: XMLDocument) -> [String: String] {
        let mappings: [(xpath: String, key: String)] = [
            ("//content", "orig"),
            ("//contentts", "ts"),
        ]
        var result: [String: String] = [:]

        for mapping in mappings {
            guard let node = (try? document.nodes(forXPath: mapping.xpath))?.first,
                  let text = node.stringValue,
                  let decoded = decodeSingleLyricText(text) else {
                continue
            }
            result[mapping.key] = decoded
        }

        return result
    }

    private func decodeSingleLyricText(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let compact = trimmed.replacingOccurrences(
            of: "\\s+",
            with: "",
            options: .regularExpression
        )

        let decoded: String
        if isStrictHex(compact) {
            guard let decryptText = decryptQQMusicQrc(compact) else { return nil }
            decoded = decryptText
        } else {
            decoded = trimmed
        }

        guard decoded.contains("<?xml") else {
            return decoded
        }

        if let nestedDoc = try? XMLUtils.create(content: decoded),
           let lyricNode = (try? nestedDoc.nodes(forXPath: "//*[@LyricContent]"))?.first as? XMLElement,
           let content = lyricNode.attribute(forName: "LyricContent")?.stringValue,
           !content.isEmpty {
            let formatted = lyricFormat(content)
            return normalizeQQQrcContent(formatted)
        }

        if let content = extractLyricContentAttribute(from: decoded), !content.isEmpty {
            let formatted = lyricFormat(content)
            return normalizeQQQrcContent(formatted)
        }

        return decoded
    }

    private func normalizeQQQrcContent(_ content: String) -> String {
        return content
            .replacingOccurrences(of: #"\s+(?=\[\d+,\d+\])"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"\]\s+\["#, with: "]\n[", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extracts the value of the `LyricContent` attribute from a raw XML string
    /// without going through an XML parser (which would collapse newlines to spaces).
    private func extractLyricContentAttribute(from xmlString: String) -> String? {
        let marker = "LyricContent=\""
        guard let markerRange = xmlString.range(of: marker) else { return nil }
        let afterMarker = xmlString[markerRange.upperBound...]

        var escaped = false
        var endQuote: String.Index?
        for idx in afterMarker.indices {
            let c = afterMarker[idx]
            if escaped {
                escaped = false
                continue
            }
            if c == "\\" {
                escaped = true
                continue
            }
            if c == "\"" {
                endQuote = idx
                break
            }
        }

        guard let endQuote else { return nil }
        let content = String(afterMarker[..<endQuote])
        return content.isEmpty ? nil : content
    }

    private func isStrictHex(_ s: String) -> Bool {
        guard !s.isEmpty, s.count % 2 == 0 else {
            return false
        }

        for c in s {
            if !(c.isNumber || (c >= "a" && c <= "f") || (c >= "A" && c <= "F")) {
                return false
            }
        }

        return true
    }

    private func fetchAlbumCoverURL(songMid: String) async -> URL? {
        let requestBody: [String: Any] = [
            "comm": ["ct": 24, "cv": 0],
            "songinfo": [
                "module": "music.pf_song_detail_svr",
                "method": "get_song_detail_yqq",
                "param": ["song_mid": songMid],
            ],
        ]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else { return nil }
        var request = URLRequest(url: URL(string: qqSearchBaseURLString2)!)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let response = try? JSONDecoder().decode(QQResponseSongDetail.self, from: data),
              !response.songinfo.data.trackInfo.album.mid.isEmpty else {
            return nil
        }
        let albumMid = response.songinfo.data.trackInfo.album.mid
        return URL(string: "https://y.gtimg.cn/music/photo_new/T002R800x800M000\(albumMid).jpg")
    }

    // Some QQ fallback lyrics use [HH:MM:SS(.xx)] timestamps, while Lyrics parser
    // accepts [MM:SS(.xx)]. Convert hours into minutes for compatibility.
    private func normalizeExtendedLrcTimestamps(_ content: String) -> String {
        let pattern = #"\[(\d+):(\d{2}):(\d{2}(?:\.\d+)?)\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return content
        }

        let nsContent = content as NSString
        let matches = regex.matches(in: content, range: NSRange(location: 0, length: nsContent.length))
        guard !matches.isEmpty else {
            return content
        }

        var normalized = content
        for match in matches.reversed() {
            guard match.numberOfRanges == 4 else { continue }
            let h = nsContent.substring(with: match.range(at: 1))
            let m = nsContent.substring(with: match.range(at: 2))
            let s = nsContent.substring(with: match.range(at: 3))
            guard let hour = Int(h), let minute = Int(m) else { continue }
            let mergedMinute = hour * 60 + minute
            let replacement = "[\(mergedMinute):\(s)]"
            if let range = Range(match.range, in: normalized) {
                normalized.replaceSubrange(range, with: replacement)
            }
        }

        return normalized
    }
}
