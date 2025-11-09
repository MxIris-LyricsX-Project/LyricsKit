/// This structure represents the full response from the Musixmatch "macro.subtitles.get" API endpoint:
/// https://apic-desktop.musixmatch.com/ws/1.1/macro.subtitles.get
struct MusixmatchResponseSingleLyrics: Decodable {
    struct Message: Decodable {
        struct Body: Decodable {
            struct MacroCalls: Decodable {
                let matcherTrackGet: MatcherTrackGet?
                // let trackLyricsGet: TrackLyricsGet?
                // let trackSnippetGet: TrackSnippetGet?
                let trackSubtitlesGet: TrackSubtitlesGet?
                // let userblobGet: UserblobGet?

                enum CodingKeys: String, CodingKey {
                    case matcherTrackGet = "matcher.track.get"
                    // case trackLyricsGet = "track.lyrics.get"
                    // case trackSnippetGet = "track.snippet.get"
                    case trackSubtitlesGet = "track.subtitles.get"
                    // case userblobGet = "userblob.get"
                }
            }
            let macroCalls: MacroCalls

            enum CodingKeys: String, CodingKey {
                case macroCalls = "macro_calls"
            }
        }

        struct Header: Decodable {
            // let available: Int?
            // let executeTime: Double?
            let hint: String?
            // let pid: Int?
            let statusCode: Int
            // let surrogateKeyList: [String]?

            enum CodingKeys: String, CodingKey {
                // case available
                // case executeTime = "execute_time"
                case hint
                // case pid
                case statusCode = "status_code"
                // case surrogateKeyList = "surrogate_key_list"
            }
        }

        let body: Body
        let header: Header
    }

    let message: Message

    struct MatcherTrackGet: Decodable {
        struct Message: Decodable {
            struct Body: Decodable {
                let track: MusixmatchResponseSearchResult.Track
            }

            struct Header: Decodable {
                // let cached: Int?
                // let confidence: Int?
                // let executeTime: Double?
                // let mode: String?
                let statusCode: Int

                enum CodingKeys: String, CodingKey {
                    // case cached
                    // case confidence
                    // case executeTime = "execute_time"
                    // case mode
                    case statusCode = "status_code"
                }
            }

            let body: Body
            let header: Header
        }

        let message: Message
    }

    // struct TrackLyricsGet: Decodable {
    //     struct Message: Decodable {
    //         struct Body: Decodable {
    //             let lyrics: Lyrics?
    //         }

    //         struct Header: Decodable {
    //             let executeTime: Double?
    //             let statusCode: Int

    //             enum CodingKeys: String, CodingKey {
    //                 case executeTime = "execute_time"
    //                 case statusCode = "status_code"
    //             }
    //         }

    //         let body: Body
    //         let header: Header
    //     }

    //     let message: Message
    // }

    struct TrackSubtitlesGet: Decodable {
        struct Message: Decodable {
            struct Body: Decodable {
                let subtitleList: [SubtitleListItem]?

                enum CodingKeys: String, CodingKey {
                    case subtitleList = "subtitle_list"
                }
            }

            struct Header: Decodable {
                // let available: Int?
                // let executeTime: Double?
                // let instrumental: Int?
                let statusCode: Int

                enum CodingKeys: String, CodingKey {
                    // case available
                    // case executeTime = "execute_time"
                    // case instrumental
                    case statusCode = "status_code"
                }
            }

            let body: Body
            let header: Header
        }

        let message: Message
    }

    // struct Lyrics: Decodable {
    //     let actionRequested: String
    //     let backlinkUrl: String
    //     let canEdit: Int
    //     let checkValidationOverridable: Int
    //     let explicit: Int
    //     let htmlTrackingUrl: String
    //     let instrumental: Int
    //     let locked: Int
    //     let lyricsBody: String
    //     let lyricsCopyright: String
    //     let lyricsId: Int
    //     let lyricsLanguage: String
    //     let lyricsLanguageDescription: String
    //     let pixelTrackingUrl: String
    //     let publishedStatus: Int
    //     let publisherList: [String]
    //     let restricted: Int
    //     let scriptTrackingUrl: String
    //     let updatedTime: String
    //     let verified: Int
    //     let writerList: [String]

    //     enum CodingKeys: String, CodingKey {
    //         case actionRequested = "action_requested"
    //         case backlinkUrl = "backlink_url"
    //         case canEdit = "can_edit"
    //         case checkValidationOverridable = "check_validation_overridable"
    //         case explicit
    //         case htmlTrackingUrl = "html_tracking_url"
    //         case instrumental
    //         case locked
    //         case lyricsBody = "lyrics_body"
    //         case lyricsCopyright = "lyrics_copyright"
    //         case lyricsId = "lyrics_id"
    //         case lyricsLanguage = "lyrics_language"
    //         case lyricsLanguageDescription = "lyrics_language_description"
    //         case pixelTrackingUrl = "pixel_tracking_url"
    //         case publishedStatus = "published_status"
    //         case publisherList = "publisher_list"
    //         case restricted
    //         case scriptTrackingUrl = "script_tracking_url"
    //         case updatedTime = "updated_time"
    //         case verified
    //         case writerList = "writer_list"
    //     }
    // }

    struct SubtitleListItem: Decodable {
        let subtitle: Subtitle
    }

    struct Subtitle: Decodable {
        // let htmlTrackingUrl: String
        // let lyricsCopyright: String
        // let pixelTrackingUrl: String
        // let publishedStatus: Int
        // let publisherList: [String]
        // let restricted: Int
        // let scriptTrackingUrl: String
        // let subtitleAvgCount: Int
        let subtitleBody: String
        // let subtitleId: Int
        // let subtitleLanguage: String
        // let subtitleLanguageDescription: String
        // let subtitleLength: Int
        // let updatedTime: String
        // let writerList: [String]

        enum CodingKeys: String, CodingKey {
            // case htmlTrackingUrl = "html_tracking_url"
            // case lyricsCopyright = "lyrics_copyright"
            // case pixelTrackingUrl = "pixel_tracking_url"
            // case publishedStatus = "published_status"
            // case publisherList = "publisher_list"
            // case restricted
            // case scriptTrackingUrl = "script_tracking_url"
            // case subtitleAvgCount = "subtitle_avg_count"
            case subtitleBody = "subtitle_body"
            // case subtitleId = "subtitle_id"
            // case subtitleLanguage = "subtitle_language"
            // case subtitleLanguageDescription = "subtitle_language_description"
            // case subtitleLength = "subtitle_length"
            // case updatedTime = "updated_time"
            // case writerList = "writer_list"
        }
    }

    // struct TrackSnippetGet: Decodable {
    //     struct Message: Decodable {
    //         struct Body: Decodable {
    //             let snippet: Snippet?
    //         }

    //         struct Header: Decodable {
    //             let executeTime: Double?
    //             let statusCode: Int

    //             enum CodingKeys: String, CodingKey {
    //                 case executeTime = "execute_time"
    //                 case statusCode = "status_code"
    //             }
    //         }

    //         let body: Body
    //         let header: Header
    //     }

    //     let message: Message
    // }

    // struct UserblobGet: Decodable {
    //     struct Message: Decodable {
    //         struct Header: Decodable {
    //             let statusCode: Int

    //             enum CodingKeys: String, CodingKey {
    //                 case statusCode = "status_code"
    //             }
    //         }

    //         let header: Header
    //     }

    //     struct Meta: Decodable {
    //         let lastUpdated: String
    //         let statusCode: Int

    //         enum CodingKeys: String, CodingKey {
    //             case lastUpdated = "last_updated"
    //             case statusCode = "status_code"
    //         }
    //     }

    //     let message: Message
    //     let meta: Meta?
    // }

    // struct Snippet: Decodable {
    //     let htmlTrackingUrl: String
    //     let instrumental: Int
    //     let pixelTrackingUrl: String
    //     let restricted: Int
    //     let scriptTrackingUrl: String
    //     let snippetBody: String
    //     let snippetId: Int
    //     let snippetLanguage: String
    //     let updatedTime: String

    //     enum CodingKeys: String, CodingKey {
    //         case htmlTrackingUrl = "html_tracking_url"
    //         case instrumental
    //         case pixelTrackingUrl = "pixel_tracking_url"
    //         case restricted
    //         case scriptTrackingUrl = "script_tracking_url"
    //         case snippetBody = "snippet_body"
    //         case snippetId = "snippet_id"
    //         case snippetLanguage = "snippet_language"
    //         case updatedTime = "updated_time"
    //     }
    // }
}
