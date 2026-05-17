import Foundation

struct NetworkPerformer: Sendable {
    let httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    func performJSON<T: Decodable>(
        _ endpoint: Endpoint,
        as type: T.Type = T.self,
        decoder: JSONDecoder = JSONDecoder()
    ) async throws -> T {
        let data = try await performData(endpoint)
        return try decode(data, as: T.self, using: decoder)
    }

    func performData(_ endpoint: Endpoint) async throws -> Data {
        let request = try endpoint.buildRequest()
        return try await executeReturningData(request)
    }

    func executeReturningData(_ request: URLRequest) async throws -> Data {
        let (data, _) = try await execute(request)
        return data
    }

    func execute(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await httpClient.data(for: request)
        } catch let error as LyricsProviderError {
            throw error
        } catch {
            throw LyricsProviderError.networkError(underlyingError: error)
        }
    }

    func decode<T: Decodable>(
        _ data: Data,
        as type: T.Type = T.self,
        using decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        do {
            return try decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            throw LyricsProviderError.decodingError(underlyingError: error)
        }
    }
}
