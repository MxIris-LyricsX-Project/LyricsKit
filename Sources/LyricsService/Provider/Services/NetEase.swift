import Foundation
import LyricsCore
import Regex
import BigInt
import CryptoSwift
import FoundationToolbox

extension LyricsProviders {
    @Loggable
    public final class NetEase {
        private let searchBaseURLString = "http://music.163.com/api/search/pc?"

//        private let lyricsBaseURLString = "http://music.163.com/api/song/lyric?"
        private let lyricsBaseURLString = "https://interface3.music.163.com/eapi/song/lyric/v1"

        public init() {}
    }
}

extension LyricsProviders.NetEase: _LyricsProvider {
    public struct LyricsToken {
        let value: NetEaseResponseSearchResult.Result.Song
    }

    public static let service: String = "NetEase"

    public func search(for request: LyricsSearchRequest) async throws -> [LyricsToken] {
        let parameter: [String: Any] = [
            "s": request.searchTerm.description,
            "offset": 0,
            "limit": 10,
            "type": 1,
        ]
        guard let url = URL(string: searchBaseURLString + parameter.stringFromHttpParameters) else {
            throw LyricsProviderError.invalidURL(urlString: searchBaseURLString + parameter.stringFromHttpParameters)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("http://music.163.com/", forHTTPHeaderField: "Referer")
        req.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15", forHTTPHeaderField: "User-Agent")

//        let url = "https://interface.music.163.com/eapi/cloudsearch/pc"
//
//        let data: [String: String] = [
//            "s": request.searchTerm.description,
//            "type": "1",
//            "limit": "30",
//            "offset": "0",
//            "total": "true",
//        ]

        do {
            let (_, response) = try await URLSession.shared.data(for: req)

            if let httpResp = response as? HTTPURLResponse, let setCookie = httpResp.allHeaderFields["Set-Cookie"] as? String, let cookieIdx = setCookie.firstIndex(of: ";") {
                let cookie = String(setCookie[..<cookieIdx])
                req.setValue(cookie, forHTTPHeaderField: "Cookie")
            }

            let (data, _) = try await URLSession.shared.data(for: req)
//            let data = try await EapiHelper.post(url: url, data: data)
//            print(try JSONSerialization.jsonObject(with: data))
            let searchResult = try JSONDecoder().decode(NetEaseResponseSearchResult.self, from: data)
            return searchResult.result.songs.map(LyricsToken.init)

        } catch let error as DecodingError {
            throw LyricsProviderError.decodingError(underlyingError: error)
        } catch {
            throw LyricsProviderError.networkError(underlyingError: error)
        }
    }

    public func fetch(with token: LyricsToken) async throws -> Lyrics {
//        let parameter: [String: Any] = [
//            "id": token.value.id,
//            "lv": 1, "kv": 1, "tv": -1,
//        ]
//        guard let url = URL(string: netEaseLyricsBaseURLString + parameter.stringFromHttpParameters) else {
//            throw LyricsProviderError.invalidURL(urlString: netEaseLyricsBaseURLString)
//        }

        let singleLyricsResponse: NetEaseResponseSingleLyrics
        do {
//            let (data, _) = try await URLSession.shared.data(from: url)
//            singleLyricsResponse = try JSONDecoder().decode(NetEaseResponseSingleLyrics.self, from: data)

            let data: [String: String] = [
                "id": token.value.id.description,
                "cp": "false",
                "lv": "0",
                "kv": "0",
                "tv": "0",
                "rv": "0",
                "yv": "0",
                "ytv": "0",
                "yrv": "0",
                "csrf_token": "",
            ]

            let raw = try await EapiHelper.post(url: lyricsBaseURLString, data: data)
            singleLyricsResponse = try JSONDecoder().decode(NetEaseResponseSingleLyrics.self, from: raw)
        } catch let error as DecodingError {
            throw LyricsProviderError.decodingError(underlyingError: error)
        } catch {
            throw LyricsProviderError.networkError(underlyingError: error)
        }

        let lyrics: Lyrics
        let transLrc = (singleLyricsResponse.tlyric?.fixedLyric).flatMap(Lyrics.init(_:))
        if let yrc = singleLyricsResponse.yrc?.fixedLyric, let pasredLyrics = Lyrics(netEaseYrcContent: yrc) {
            lyrics = pasredLyrics
        } else if let kLrc = (singleLyricsResponse.klyric?.fixedLyric).flatMap(Lyrics.init(netEaseKLyricContent:)) {
            transLrc.map(kLrc.forceMerge)
            lyrics = kLrc
        } else if let lrc = (singleLyricsResponse.lrc?.fixedLyric).flatMap(Lyrics.init(_:)) {
            transLrc.map(lrc.merge)
            lyrics = lrc
        } else {
            throw LyricsProviderError.processingFailed(reason: "No valid lyric content found in NetEase response.")
        }

        lyrics.idTags[.title] = token.value.name
        lyrics.idTags[.artist] = token.value.artists.first?.name
        lyrics.idTags[.album] = token.value.album.name
        lyrics.idTags[.lrcBy] = singleLyricsResponse.lyricUser?.nickname
        lyrics.length = Double(token.value.duration) / 1000
        lyrics.metadata.artworkURL = token.value.album.picUrl
        lyrics.metadata.serviceToken = "\(token.value.id)"

        return lyrics
    }
}

private let netEaseTimeTagFixer = try! Regex(#"(\[\d+:\d+):(\d+\])"#) // swiftlint:disable:this force_try

extension NetEaseResponseSingleLyrics.Lyric {
    fileprivate var fixedLyric: String? {
        return lyric?.replacingMatches(of: netEaseTimeTagFixer, with: "$1.$2")
    }
}

@Loggable
private enum EapiHelper {
    private static let userAgent = "Mozilla/5.0 (Linux; Android 9; PCT-AL10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.64 HuaweiBrowser/10.0.3.311 Mobile Safari/537.36"
    private static let eapiKey = "e82ckenh8dichen8".data(using: .ascii)!

    static func post(url: String, data: [String: String]) async throws -> Data {
        let httpClient = URLSession.shared

        var headers: [String: String] = [
            "User-Agent": userAgent,
            "Referer": "https://music.163.com/",
        ]

        let header: [String: String] = [
            "__csrf": "",
            "appver": "8.0.0",
            "buildver": String(getCurrentTotalSeconds()),
            "channel": "",
            "deviceId": "",
            "mobilename": "",
            "resolution": "1920x1080",
            "os": "android",
            "osver": "",
            "requestId": "\(getCurrentTotalMilliseconds())_\(String(format: "%04d", Int.random(in: 0 ... 999)))",
            "versioncode": "140",
            "MUSIC_U": "",
        ]

        let cookie = header.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        headers["Cookie"] = cookie

        var mutableData = data
        let headerJson = try JSONSerialization.data(withJSONObject: header)
        mutableData["header"] = String(data: headerJson, encoding: .utf8) ?? "{}"

        let data2 = eApi(url: url, object: mutableData)
        let modifiedUrl = url.replacingOccurrences(of: #"\w*api"#, with: "eapi", options: .regularExpression)

        var request = URLRequest(url: URL(string: modifiedUrl)!)
        request.httpMethod = "POST"

        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let formData = data2.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        request.httpBody = formData.data(using: .utf8)

        let (responseData, _) = try await httpClient.data(for: request)
        return responseData
    }

    private static func getCurrentTotalSeconds() -> UInt64 {
        return UInt64(Date().timeIntervalSince1970)
    }

    private static func getCurrentTotalMilliseconds() -> UInt64 {
        return UInt64(Date().timeIntervalSince1970 * 1000)
    }

    private static func eApi(url: String, object: Any) -> [String: String] {
        let modifiedUrl = url
            .replacingOccurrences(of: "https://interface3.music.163.com/e", with: "/")
            .replacingOccurrences(of: "https://interface.music.163.com/e", with: "/")

        let jsonData = try! JSONSerialization.data(withJSONObject: object)
        let text = String(data: jsonData, encoding: .utf8) ?? "{}"

        let message = "nobody\(modifiedUrl)use\(text)md5forencrypt"
        let digest = md5Hash(string: message)
        let data = "\(modifiedUrl)-36cd479b6b5-\(text)-36cd479b6b5-\(digest)"

        let encrypted = aesEncryptECB(data: data.data(using: .utf8)!, key: eapiKey)
        let hexString = encrypted.map { String(format: "%02X", $0) }.joined()

        return ["params": hexString]
    }

    private static func decrypt(cipherBuffer: Data) -> Data? {
        return aesDecryptECB(data: cipherBuffer, key: eapiKey)
    }

    private static func aesEncryptECB(data: Data, key: Data) -> Data {
        do {
            let keyBytes = Array(key)
            let dataBytes = Array(data)

            let aes = try AES(key: keyBytes, blockMode: ECB(), padding: .pkcs7)
            let encrypted = try aes.encrypt(dataBytes)

            return Data(encrypted)
        } catch {
            #log(.error, "AES ECB encryption error: \(error)")
            return Data()
        }
    }

    private static func aesDecryptECB(data: Data, key: Data) -> Data? {
        do {
            let keyBytes = Array(key)
            let dataBytes = Array(data)

            let aes = try AES(key: keyBytes, blockMode: ECB(), padding: .pkcs7)
            let decrypted = try aes.decrypt(dataBytes)

            return Data(decrypted)
        } catch {
            #log(.error, "AES ECB decryption error: \(error)")
            return nil
        }
    }

    private static func md5Hash(string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        let bytes = Array(data)
        let digest = bytes.md5()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

extension Data {
    fileprivate func toHexString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }

    fileprivate func toHexStringUpper() -> String {
        return map { String(format: "%02X", $0) }.joined()
    }
}

extension String {
    fileprivate func toByteArrayUtf8() -> Data? {
        return data(using: .utf8)
    }
}
