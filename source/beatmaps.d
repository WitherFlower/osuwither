import std.sumtype;

// Change this when adding a new ruleset
enum RulesetCount = 4;

// Difficulty Settings

struct OsuBeatmapDifficultySettings {
    float circleSize;
    float approachRate;
    float overallDifficulty;
    float hpDrain;
}

struct TaikoBeatmapDifficultySettings {
    float overallDifficulty;
    float hpDrain;
    // float scrollSpeed; // This should be a thing(?) but I don't think it's gettable from the API
}

struct CatchBeatmapDifficultySettings {
    float circleSize;
    float approachRate;
    float hpDrain;
}

struct ManiaBeatmapDifficultySettings {
    float keyCount;
    float overallDifficulty;
    float hpDrain;
}

alias BeatmapDifficultySettings = SumType!(
    OsuBeatmapDifficultySettings,
    TaikoBeatmapDifficultySettings,
    CatchBeatmapDifficultySettings,
    ManiaBeatmapDifficultySettings,
);

static assert(BeatmapDifficultySettings.Types.length == RulesetCount);

// Object Counts

struct OsuObjectCounts {
    int circleCount;
    int sliderCount;
    int spinnerCount;
}

struct TaikoObjectCounts {
    int hitCount;
    int drumrollCount;
    int swellCount;
}

struct CatchObjectCounts {
    int fruitCount;
    int juiceCount;
    int bananaCount;
}

struct ManiaObjectCounts {
    int noteCount;
    int holdNoteCount;
}

alias ObjectCounts = SumType!(
    OsuObjectCounts,
    TaikoObjectCounts,
    CatchObjectCounts,
    ManiaObjectCounts,
);

static assert(ObjectCounts.Types.length == RulesetCount);

// Other Types

// This is its own type because maps retain the mapper's name at the time the map got ranked
struct Mapper {
    int userId;
    string username;
}

enum RankedStatus : int {
    Graveyard = -2,
    Wip       = -1,
    Pending   =  0,
    Ranked    =  1,
    Approved  =  2,
    Qualified =  3,
    Loved     =  4,
}

enum Ruleset : int {
    Osu,
    Taiko,
    Catch,
    Mania,
}

// Beatmap Types

struct Beatmap {
    import std.datetime.date : Date;
    import core.time         : Duration;

    RankedStatus rankedStatus;
    Date         submittedDate;
    Date         rankedDate;
    Date         updatedDate;
    int          beatmapId;
    int          beatmapSetId;
    float        bpm;
    Mapper[]     mappers;
    float        starRating;
    Date         lastStarRatingUpdate; // Used for refetch or recalc
    Ruleset      ruleset;
    Duration     length;
    Duration     drainLength;
    string       difficultyName;
    ObjectCounts objectCounts;
    int          maxCombo;
}

struct BeatmapSet {
    int    beatmapSetId;
    Mapper creator; // Tester si l'APIv1 renvoie toujours le créateur du mapset (même sur les guest diffs)
    string artist;
    string source;
    string title;
    string tags;
    bool   hasStoryboard;
    bool   hasVideo;
    bool   downloadUnavailable;
    bool   audioUnavailable;
}

/+

 NOTE: Que faire des MD5 ?
    Ne pas faire confiance au md5. Quand j'implémenterai les collections :
        - Si osu!lazer supporte les imports avec un format de fichier bien défini, ignorer la suite
        - Sinon, on lira les md5 (ou autre infos nécessaires à l'import de collection) dans la base de données de lazer elle-même
    Dans tous les cas, pas de stockage de md5, car l'info est périssable

APIv2

Beatmap

beatmapset_id     integer
difficulty_rating float
id                integer
mode              Ruleset
status            string 	See Rank status for list of possible values.
total_length      integer
user_id           integer
version           string

Optional attributes:
beatmapset             Beatmapset|BeatmapsetExtended|null 	Beatmapset for Beatmap object, BeatmapsetExtended for BeatmapExtended object. null if the beatmap doesn't have associated beatmapset (e.g. deleted).
checksum               string?
current_user_playcount integer
failtimes              Failtimes
max_combo              integer
owners                 BeatmapOwner[] 	List of owners (mappers) for the Beatmap.

Failtimes
All fields are optional but there's always at least one field returned.
exit integer[]? 	Array of length 100.
fail integer[]? 	Array of length 100.

BeatmapExtended : Extends Beatmap

accuracy       float
ar             float
beatmapset_id  integer
bpm            float?
convert        boolean
count_circles  integer // TODO: Besoin d'établir comment ça se comporte pour les autres mods (putain)
count_sliders  integer
count_spinners integer
cs             float
deleted_at     Timestamp?
drain          float
hit_length     integer
is_scoreable   boolean
last_updated   Timestamp
mode_int       integer
passcount      integer
playcount      integer
ranked         integer      See Rank status for list of possible values.
url            string

Ruleset : string ???
Timestamp : string

BeatmapOwner
id       integer 	User id of the Beatmap owner.
username string 	Username of the Beatmap owner.

BeatmapSet
artist          string
artist_unicode  string
covers          Covers
creator         string
favourite_count integer
id              integer
nsfw            boolean
offset          integer
play_count      integer
preview_url     string
source          string
status          string
spotlight       boolean
title           string
title_unicode   string
user_id         integer
video           boolean

optional :
beatmaps                (Beatmap|BeatmapExtended)[]
converts
current_nominations     Nomination[]
current_user_attributes
description
discussions
events
genre
has_favourited          boolean
language
nominations
pack_tags               string[]
ratings
recent_favourites
related_users
user
track_id                integer

Covers
cover        string
cover@2x     string
card         string
card@2x      string
list         string
list@2x      string
slimcover    string
slimcover@2x string

Nomination
beatmapset_id integer
rulesets      Ruleset[]
reset         boolean
user_id       integer

BeatmapSetExtended

availability.download_disabled boolean
availability.more_information  string?
bpm                            float
can_be_hyped                   boolean
deleted_at                     Timestamp?
discussion_enabled             boolean 	Deprecated, all beatmapsets now have discussion enabled.
discussion_locked              boolean
hype.current                   integer
hype.required                  integer
is_scoreable                   boolean
last_updated                   Timestamp
legacy_thread_url              string?
nominations_summary.current    integer
nominations_summary.required   integer
ranked                         integer 	See Rank status for list of possible values.
ranked_date                    Timestamp?
rating                         float
source                         string
storyboard                     boolean
submitted_date                 Timestamp?
tags                           string

APIv1

[{
    "approved"             : "1",                   // 4 = loved, 3 = qualified, 2 = approved, 1 = ranked, 0 = pending, -1 = WIP, -2 = graveyard
    "submit_date"          : "2013-05-15 11:32:26", // date submitted, in UTC
    "approved_date"        : "2013-07-06 08:54:46", // date ranked, in UTC
    "last_update"          : "2013-07-06 08:51:22", // last update date, in UTC. May be after approved_date if map was unranked and reranked.
    "artist"               : "Luxion",
    "beatmap_id"           : "252002",              // beatmap_id is per difficulty
    "beatmapset_id"        : "93398",               // beatmapset_id groups difficulties into a set
    "bpm"                  : "196",
    "creator"              : "RikiH_",
    "creator_id"           : "686209",
    "difficultyrating"     : "5.744717597961426",   // The number of stars the map would have in-game and on the website
    "diff_aim"             : "2.7706098556518555",
    "diff_speed"           : "2.9062750339508057",
    "diff_size"            : "4",                   // Circle size value (CS)
    "diff_overall"         : "8",                   // Overall difficulty (OD)
    "diff_approach"        : "9",                   // Approach Rate (AR)
    "diff_drain"           : "7",                   // Health drain (HP)
    "hit_length"           : "114",                 // seconds from first note to last note not including breaks
    "source"               : "BMS",
    "genre_id"             : "2",                   // 0 = any, 1 = unspecified, 2 = video game, 3 = anime, 4 = rock, 5 = pop, 6 = other, 7 = novelty, 9 = hip hop, 10 = electronic, 11 = metal, 12 = classical, 13 = folk, 14 = jazz (note that there's no 8)
    "language_id"          : "5",                   // 0 = any, 1 = unspecified, 2 = english, 3 = japanese, 4 = chinese, 5 = instrumental, 6 = korean, 7 = french, 8 = german, 9 = swedish, 10 = spanish, 11 = italian, 12 = russian, 13 = polish, 14 = other
    "title"                : "High-Priestess",      // song name
    "total_length"         : "146",                 // seconds from first note to last note including breaks
    "version"              : "Overkill",            // difficulty name
    "file_md5"             : "c8f08438204abfcdd1a748ebfae67421",            
                                                    // md5 hash of the beatmap
    "mode"                 : "0",                   // game mode,
    "tags"                 : "kloyd flower roxas",  // Beatmap tags separated by spaces.
    "favourite_count"      : "140",                 // Number of times the beatmap was favourited. (Americans: notice the ou!)
    "rating"               : "9.44779",
    "playcount"            : "94637",               // Number of times the beatmap was played
    "passcount"            : "10599",               // Number of times the beatmap was passed, completed (the user didn't fail or retry)
    "count_normal"         : "388",
    "count_slider"         : "222",
    "count_spinner"        : "3",
    "max_combo"            : "899",                 // The maximum combo a user can reach playing this beatmap.
    "storyboard"           : "0",                   // If this beatmap has a storyboard
    "video"                : "0",                   // If this beatmap has a video
    "download_unavailable" : "0",                   // If the download for this beatmap is unavailable (old map, etc.)
    "audio_unavailable"    : "0"                    // If the audio for this beatmap is unavailable (DMCA takedown, etc.)
}, { ... }, ...]
+/
