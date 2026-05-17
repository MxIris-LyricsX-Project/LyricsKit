import Foundation
import CryptoSwift
import FoundationToolbox

@Loggable
struct NetEaseEapiClient: Sendable {
    let httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    static let eapiKey: Data = Data("e82ckenh8dichen8".utf8)
    private static let userAgent: String = "Mozilla/5.0 (Linux; Android 9; PCT-AL10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.64 HuaweiBrowser/10.0.3.311 Mobile Safari/537.36"

    func post(url urlString: String, payload: [String: String]) async throws -> Data {
        let header = makeHeader()
        let cookie = header.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        let headerJson = try JSONSerialization.data(withJSONObject: header)
        let headerString = String(data: headerJson, encoding: .utf8) ?? "{}"

        var payloadWithHeader = payload
        payloadWithHeader["header"] = headerString

        let encryptedParams = try Self.eApiParams(url: urlString, object: payloadWithHeader)
        let modifiedUrl = Self.normalizeEapiURL(urlString)

        let bodyString = encryptedParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")" }
            .joined(separator: "&")
        guard let bodyData = bodyString.data(using: .utf8) else {
            throw LyricsProviderError.processingFailed(reason: "Failed to encode eapi body")
        }

        var request = try Endpoint.absolute(
            modifiedUrl,
            method: .post,
            headers: [
                "User-Agent": Self.userAgent,
                "Referer": "https://music.163.com/",
                "Cookie": cookie,
            ],
            body: bodyData
        )
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let performer = NetworkPerformer(httpClient: httpClient)
        return try await performer.executeReturningData(request)
    }

    private func makeHeader() -> [String: String] {
        [
            "__csrf": "",
            "appver": "8.0.0",
            "buildver": String(Self.currentTotalSeconds()),
            "channel": "",
            "deviceId": "",
            "mobilename": "",
            "resolution": "1920x1080",
            "os": "android",
            "osver": "",
            "requestId": "\(Self.currentTotalMilliseconds())_\(String(format: "%04d", Int.random(in: 0 ... 999)))",
            "versioncode": "140",
            "MUSIC_U": "",
        ]
    }

    private static func currentTotalSeconds() -> UInt64 {
        UInt64(Date().timeIntervalSince1970)
    }

    private static func currentTotalMilliseconds() -> UInt64 {
        UInt64(Date().timeIntervalSince1970 * 1000)
    }

    /// Rewrites the API path component (e.g. `weapi`, `api`, `linuxapi`) to `eapi`
    /// so the encrypted-params endpoint is targeted regardless of the input flavor.
    static func normalizeEapiURL(_ url: String) -> String {
        url.replacingOccurrences(of: #"\w*api"#, with: "eapi", options: .regularExpression)
    }

    static func eApiParams(url: String, object: Any) throws -> [String: String] {
        let modifiedUrl = url
            .replacingOccurrences(of: "https://interface3.music.163.com/e", with: "/")
            .replacingOccurrences(of: "https://interface.music.163.com/e", with: "/")

        let jsonData: Data
        do {
            jsonData = try JSONSerialization.data(withJSONObject: object)
        } catch {
            throw LyricsProviderError.processingFailed(reason: "Failed to serialize eapi payload: \(error.localizedDescription)")
        }
        let text = String(data: jsonData, encoding: .utf8) ?? "{}"

        let message = "nobody\(modifiedUrl)use\(text)md5forencrypt"
        let digest = md5Hash(message)
        let data = "\(modifiedUrl)-36cd479b6b5-\(text)-36cd479b6b5-\(digest)"

        guard let dataBytes = data.data(using: .utf8) else {
            throw LyricsProviderError.processingFailed(reason: "Failed to encode eapi data string")
        }
        let encrypted = try aesEncryptECB(data: dataBytes, key: eapiKey)
        let hexString = encrypted.map { String(format: "%02X", $0) }.joined()
        return ["params": hexString]
    }

    static func aesEncryptECB(data: Data, key: Data) throws -> Data {
        do {
            let aes = try AES(key: Array(key), blockMode: ECB(), padding: .pkcs7)
            let encrypted = try aes.encrypt(Array(data))
            return Data(encrypted)
        } catch {
            throw LyricsProviderError.processingFailed(reason: "AES ECB encryption failed: \(error.localizedDescription)")
        }
    }

    static func aesDecryptECB(data: Data, key: Data) throws -> Data {
        do {
            let aes = try AES(key: Array(key), blockMode: ECB(), padding: .pkcs7)
            let decrypted = try aes.decrypt(Array(data))
            return Data(decrypted)
        } catch {
            throw LyricsProviderError.processingFailed(reason: "AES ECB decryption failed: \(error.localizedDescription)")
        }
    }

    static func md5Hash(_ string: String) -> String {
        guard let data = string.data(using: .utf8) else { return "" }
        return Array(data).md5().map { String(format: "%02x", $0) }.joined()
    }
}
