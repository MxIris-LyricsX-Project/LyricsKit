/// This structure represents the full response from the Musixmatch "track.search" API endpoint:
/// https://apic-desktop.musixmatch.com/ws/1.1/track.search
struct MusixmatchResponseSearchResult: Decodable {
    struct Message: Decodable {
        struct Body: Decodable {
            struct TrackContainer: Decodable {
                let track: Track
            }

            let trackList: [TrackContainer]?

            enum CodingKeys: String, CodingKey {
                case trackList = "track_list"
            }
        }

        struct Header: Decodable {
            // let available: Int?
            // let executeTime: Double?
            let hint: String?
            let statusCode: Int

            enum CodingKeys: String, CodingKey {
                // case available
                // case executeTime = "execute_time"
                case hint
                case statusCode = "status_code"
            }
        }

        let body: Body?
        let header: Header
    }

    let message: Message

    struct Track: Decodable {
        /// Preference order: 800x800 -> 500x500 -> 350x350 -> 100x100 -> empty string
        var albumCoverBest: String {
            if let s = albumCoverart800x800, !s.isEmpty { return s }
            if let s = albumCoverart500x500, !s.isEmpty { return s }
            if let s = albumCoverart350x350, !s.isEmpty { return s }
            if let s = albumCoverart100x100, !s.isEmpty { return s }
            return ""
        }
        
        let albumCoverart100x100: String?
        let albumCoverart350x350: String?
        let albumCoverart500x500: String?
        let albumCoverart800x800: String?
        // let albumId: Int?
        let albumName: String
        // let albumVanityId: String?
        // let artistId: Int?
        // let artistMbid: String?
        let artistName: String
        // let commontrack7digitalIds: [Int]?
        // let commontrackId: Int?
        // let commontrackIsrcs: [[String]]?
        // let commontrackItunesIds: [String]?
        // let commontrackSpotifyIds: [String]?
        // let commontrackVanityId: String?
        // let explicit: Int?
        // let firstReleaseDate: String?
        // let hasLyrics: Int?
        // let hasLyricsCrowd: Int?
        // let hasRichsync: Int?
        let hasSubtitles: Int
        // let hasTrackStructure: Int?
        let instrumental: Int
        // let lyricsId: Int?
        // let numFavourite: Int?
        // let primaryGenres: PrimaryGenres?
        // let restricted: Int?
        // let secondaryGenres: PrimaryGenres?
        // let subtitleId: Int?
        // let trackEditUrl: String?
        let trackId: Int
        // let trackIsrc: String?
        let trackLength: Int
        // let trackLyricsTranslationStatus: [TranslationStatus]?
        // let trackMbid: String?
        let trackName: String
        // let trackNameTranslationList: [String]?
        // let trackRating: Int?
        // let trackShareUrl: String?
        // let trackSoundcloudId: Int?
        let trackSpotifyId: String
        // let trackXboxmusicId: String?
        // let updatedTime: String?

        enum CodingKeys: String, CodingKey {
            case albumCoverart100x100 = "album_coverart_100x100"
            case albumCoverart350x350 = "album_coverart_350x350"
            case albumCoverart500x500 = "album_coverart_500x500"
            case albumCoverart800x800 = "album_coverart_800x800"
            // case albumId = "album_id"
            case albumName = "album_name"
            // case albumVanityId = "album_vanity_id"
            // case artistId = "artist_id"
            // case artistMbid = "artist_mbid"
            case artistName = "artist_name"
            // case commontrack7digitalIds = "commontrack_7digital_ids"
            // case commontrackId = "commontrack_id"
            // case commontrackIsrcs = "commontrack_isrcs"
            // case commontrackItunesIds = "commontrack_itunes_ids"
            // case commontrackSpotifyIds = "commontrack_spotify_ids"
            // case commontrackVanityId = "commontrack_vanity_id"
            // case explicit
            // case firstReleaseDate = "first_release_date"
            // case hasLyrics = "has_lyrics"
            // case hasLyricsCrowd = "has_lyrics_crowd"
            // case hasRichsync = "has_richsync"
            case hasSubtitles = "has_subtitles"
            // case hasTrackStructure = "has_track_structure"
            case instrumental
            // case lyricsId = "lyrics_id"
            // case numFavourite = "num_favourite"
            // case primaryGenres = "primary_genres"
            // case restricted
            // case secondaryGenres = "secondary_genres"
            // case subtitleId = "subtitle_id"
            // case trackEditUrl = "track_edit_url"
            case trackId = "track_id"
            // case trackIsrc = "track_isrc"
            case trackLength = "track_length"
            // case trackLyricsTranslationStatus = "track_lyrics_translation_status"
            // case trackMbid = "track_mbid"
            case trackName = "track_name"
            // case trackNameTranslationList = "track_name_translation_list"
            // case trackRating = "track_rating"
            // case trackShareUrl = "track_share_url"
            // case trackSoundcloudId = "track_soundcloud_id"
            case trackSpotifyId = "track_spotify_id"
            // case trackXboxmusicId = "track_xboxmusic_id"
            // case updatedTime = "updated_time"
        }
    }

    // struct PrimaryGenres: Decodable {
    //     struct MusicGenreContainer: Decodable {
    //         struct MusicGenre: Decodable {
    //             let musicGenreId: Int?
    //             let musicGenreName: String?
    //             let musicGenreNameExtended: String?
    //             let musicGenreParentId: Int?
    //             let musicGenreVanity: String?

    //             enum CodingKeys: String, CodingKey {
    //                 case musicGenreId = "music_genre_id"
    //                 case musicGenreName = "music_genre_name"
    //                 case musicGenreNameExtended = "music_genre_name_extended"
    //                 case musicGenreParentId = "music_genre_parent_id"
    //                 case musicGenreVanity = "music_genre_vanity"
    //             }
    //         }

    //         let musicGenre: MusicGenre?

    //         enum CodingKeys: String, CodingKey {
    //             case musicGenre = "music_genre"
    //         }
    //     }

    //     let musicGenreList: [MusicGenreContainer]?

    //     enum CodingKeys: String, CodingKey {
    //         case musicGenreList = "music_genre_list"
    //     }
    // }

    // struct TranslationStatus: Decodable {
    //     let from: String?
    //     let perc: Int?
    //     let to: String?
    // }
}
