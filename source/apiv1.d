module apiv1;

import datatypes;
import deserialize;
import result;

import std.conv;
import std.format;
import std.json;
import std.stdio;

import requests;

struct Beatmap {
    string approved; // 4 = loved, 3 = qualified, 2 = approved, 1 = ranked, 0 = pending, -1 = WIP, -2 = graveyard
    string submit_date;
    string approved_date;
    string artist;
    string beatmap_id;
    string beatmapset_id;
    string bpm;
    string creator; // Mapset creator (I think)
    string difficultyrating;
    string diff_aim;
    string diff_speed;
    string diff_size;
    string diff_overall;
    string diff_approach;
    string diff_drain;
    string hit_length;
    string source;
    string genre_id;
    string language_id;
    string title;
    string total_length;
    // Aliasing is necessary here because `version` is a keyword in D
    @AliasOf("version") string difficulty_name;
    string file_md5;
    string mode;
    string tags;
    string favourite_count;
    string rating;
    string playcount;
    string passcount;
    string count_normal;
    string count_slider;
    string count_spinner;
    string max_combo;
    string storyboard;
    string video;
    string download_unavailable;
    string audio_unavailable;
    string packs; // This is not in the docs but the API seems to be returning it
}

RankedStatus toRankedStatus(string apiV1RankedStatus)
in (apiV1RankedStatus !is null) {
    int rankedStatusNumber = apiV1RankedStatus.to!int;
    with(RankedStatus) final switch(rankedStatusNumber) {
        case -2: return Graveyard;
        case -1: return Wip;
        case  0: return Pending;
        case  1: return Ranked;
        case  2: return Approved;
        case  3: return Qualified;
        case  4: return Loved;
    }
}

Ruleset toRuleset(string apiV1Mode)
in (apiV1Mode !is null) {
    int rankedStatusNumber = apiV1Mode.to!int;
    with(Ruleset) final switch(rankedStatusNumber) {
        case  0: return Osu;
        case  1: return Taiko;
        case  2: return Catch;
        case  3: return Mania;
    }
}

ObjectCounts getObjectCounts(Beatmap beatmap) {
    Ruleset ruleset = beatmap.mode.toRuleset();
    with(Ruleset) final switch (ruleset) {
        case Osu:   return ObjectCounts(OsuObjectCounts(
                        circleCount:    beatmap.count_normal.to!int,
                        sliderCount:    beatmap.count_slider.to!int,
                        spinnerCount:   beatmap.count_spinner.to!int,
                    ));
        case Taiko: return ObjectCounts(TaikoObjectCounts(
                        hitCount:       beatmap.count_normal.to!int,
                        drumrollCount:  beatmap.count_slider.to!int,
                        swellCount:     beatmap.count_spinner.to!int,
                    ));
        case Catch: return ObjectCounts(CatchObjectCounts(
                        fruitCount:     beatmap.count_normal.to!int,
                        juiceCount:     beatmap.count_slider.to!int,
                        bananaCount:    beatmap.count_spinner.to!int,
                    ));
        case Mania: return ObjectCounts(ManiaObjectCounts(
                        noteCount:      beatmap.count_normal.to!int,
                        holdNoteCount:  beatmap.count_slider.to!int,
                    ));
    }
}

import std.datetime.systime  : SysTime;
import std.datetime.date     : DateTime;
import std.datetime.timezone : UTC;

SysTime parseApiV1Date(string date) {
    int year, month, day, hour, minutes, seconds;
    date.formattedRead!"%d-%d-%d %d:%d:%d"(year, month, day, hour, minutes, seconds);
    return SysTime(DateTime(year, month, day, hour, minutes, seconds), tz: UTC());
}

unittest {
    import core.time : TimeException;
    import std.exception : assertThrown;
    assert(parseApiV1Date("2007-10-06 17:46:31") == SysTime(DateTime(2007, 10, 6, 17, 46, 31), tz: UTC()));
    assertThrown!TimeException(parseApiV1Date("9999999-99-99 99:99:99"));
    assertThrown!TimeException(parseApiV1Date(null));
}

enum ErrorType {
    InvalidMaxCombo,
}

/+
  This function is here, because if the API changes, it will also change,
  and it's better if the change is local to this file as opposed to being split apart.

  The signature is kinda stupid, the hope is that someone using it outside this module
  can do the following

  import datatypes;
  import apiv1 : ApiV1Beatmap = Beatmap;
  ApiV1Beatmap apiV1Beatmap;
  Beatmap beatmap = apiV1Beatmap.toBeatmap();
+/
datatypes.Beatmap toBeatmap(Beatmap beatmap, out ErrorType[] errors) {
    import std.datetime.systime : SysTime, Clock;
    import core.time            : seconds;
    auto result = datatypes.Beatmap(
        rankedStatus:         beatmap.approved.toRankedStatus(),
        submittedDate:        beatmap.submit_date.parseApiV1Date(),
        rankedDate:           beatmap.approved_date.parseApiV1Date().orDefault(),
        updatedDate:          beatmap.approved_date.parseApiV1Date().orDefault(),
        beatmapId:            beatmap.beatmap_id.to!int,
        beatmapSetId:         beatmap.beatmapset_id.to!int,
        bpm:                  beatmap.bpm.to!float.orDefault(),
        mappers:              [],
        starRating:           beatmap.difficultyrating.to!float.orDefault(),
        lastStarRatingUpdate: Clock.currTime(),
        ruleset:              beatmap.mode.toRuleset(),
        length:               seconds(beatmap.total_length.to!int),
        drainLength:          seconds(beatmap.hit_length.to!int),
        difficultyName:       beatmap.difficulty_name,
        objectCounts:         beatmap.getObjectCounts(),
        maxCombo:             beatmap.max_combo.to!int.orDefaultWithError(ErrorType.InvalidMaxCombo, errors),
    );
    return result;
}

Beatmap[] getBeatmaps(string apiKey, string since = null, int limit = 500) {
    Request request = Request();
    request.addHeaders([
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
    ]);
    request.keepAlive = false;
    // request.verbosity = 2;
    Response response = request.post(
        "https://osu.ppy.sh/api/get_beatmaps",
        queryParams(
            "k",     apiKey,
            // "limit", 10,
            "since", since,
            "limit", limit,
        ),
    );
    /* writeln(response.responseBody); */
    JSONValue responseJson = response.responseBody.to!string().parseJSON();

    Beatmap[] result = void;
    string error = "";
    if (!deserializeJson(responseJson, result, error)) writeln(error);
    return result;
}

/+
From the APIv1 docs, get_beatmaps endpoint

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
