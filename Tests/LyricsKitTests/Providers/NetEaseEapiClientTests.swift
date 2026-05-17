import Testing
import Foundation
@testable import LyricsService

struct NetEaseEapiClientTests {
    @Test func md5HashKnownVectors() {
        // RFC 1321 standard test vectors
        #expect(NetEaseEapiClient.md5Hash("") == "d41d8cd98f00b204e9800998ecf8427e")
        #expect(NetEaseEapiClient.md5Hash("a") == "0cc175b9c0f1b6a831c399e269772661")
        #expect(NetEaseEapiClient.md5Hash("abc") == "900150983cd24fb0d6963f7d28e17f72")
        #expect(NetEaseEapiClient.md5Hash("message digest") == "f96b697d7cb7938d525a2f31aaf161d0")
    }

    @Test func aesEncryptDecryptRoundTrip() throws {
        let key = NetEaseEapiClient.eapiKey
        let plaintext = Data("Hello, eapi world!".utf8)
        let encrypted = try NetEaseEapiClient.aesEncryptECB(data: plaintext, key: key)
        #expect(encrypted != plaintext)
        let decrypted = try NetEaseEapiClient.aesDecryptECB(data: encrypted, key: key)
        #expect(decrypted == plaintext)
    }

    @Test func aesEncryptIsDeterministicForSameInput() throws {
        let key = NetEaseEapiClient.eapiKey
        let plaintext = Data("Deterministic".utf8)
        let firstEncryption = try NetEaseEapiClient.aesEncryptECB(data: plaintext, key: key)
        let secondEncryption = try NetEaseEapiClient.aesEncryptECB(data: plaintext, key: key)
        #expect(firstEncryption == secondEncryption)
    }

    @Test func eApiParamsReturnsParamsKeyWithHexString() throws {
        let result = try NetEaseEapiClient.eApiParams(
            url: "https://interface3.music.163.com/eapi/song/lyric/v1",
            object: ["id": "12345"]
        )
        let hex = try #require(result["params"])
        // Hex string of AES output: even length, uppercase A-F + digits.
        #expect(hex.count % 2 == 0)
        #expect(hex.allSatisfy { ($0.isNumber) || ($0 >= "A" && $0 <= "F") })
        // AES ECB output is a multiple of 16 bytes -> hex length multiple of 32.
        #expect(hex.count % 32 == 0)
    }

    @Test func eApiParamsIsDeterministicForSameInput() throws {
        let url = "https://interface3.music.163.com/eapi/song/lyric/v1"
        let payload: [String: String] = ["id": "12345", "csrf_token": ""]
        let first = try NetEaseEapiClient.eApiParams(url: url, object: payload)
        let second = try NetEaseEapiClient.eApiParams(url: url, object: payload)
        #expect(first == second)
    }

    @Test func normalizeEapiURLRewritesApiToEapi() {
        let input = "https://interface.music.163.com/api/song/lyric/v1"
        let normalized = NetEaseEapiClient.normalizeEapiURL(input)
        #expect(normalized.contains("/eapi/"))
        #expect(!normalized.contains("/api/"))
    }
}
