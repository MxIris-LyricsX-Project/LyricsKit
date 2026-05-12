import Foundation
import LyricsCore
import FoundationToolbox

extension LyricsProviders {
    @Loggable
    public final class Group: LyricsProvider {
        public let providers: [LyricsProvider]

        public init(service: [LyricsProviders.Service] = LyricsProviders.Service.noAuthenticationRequiredServices) {
            self.providers = service.map { $0.create() }
        }

        public init(providers: [LyricsProvider]) {
            self.providers = providers
        }

        public func lyrics(for request: LyricsSearchRequest) -> AsyncThrowingStream<Lyrics, Error> {
            return AsyncThrowingStream { continuation in
                Task {
                    for provider in providers {
                        do {
                            for try await lyric in provider.lyrics(for: request) {
                                continuation.yield(lyric)
                            }
                        } catch {
                            #log(.error, "A provider in the group failed: \(error)")
                        }
                    }
                    continuation.finish()
                }
            }
        }
    }
}
