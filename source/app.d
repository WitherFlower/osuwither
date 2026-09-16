import database;
import datatypes;
import deserialize;

import std.conv;
import std.datetime;
import std.json;
import std.stdio;
import std.string;
import std.sumtype;
import core.thread;
import etc.c.sqlite3;

import requests;

struct Settings {
    string clientSecret;
    string apiV1Key;
}

void parseSettings(string fileName, out Settings settings) {
    File settingsFile = File(fileName, "r");
    string[string] fileContents;
    while (!settingsFile.eof()) {
        string line = settingsFile.readln();
        if (line.indexOf("=") < 0) continue;
        string key = line[0 .. line.indexOf("=")].strip();
        string value = line[line.indexOf("=") + 1 .. $].strip(); // Fucking newline
        fileContents[key] = value;
    }
    foreach (string member; __traits(allMembers, typeof(settings))) {
        __traits(getMember, settings, member) = fileContents[member];
    }
}

extern (C)
int callback(void *notUsed, int argc, char **argv, char **azColName) {
    int i;
    for (i = 0; i < argc; i++) {
        printf("%s = %s\n", azColName[i], argv[i] ? argv[i] : "NULL");
    }
    printf("\n");
    return 0;
}

struct TokenResponse {
    int expires_in;
    string access_token;
    string token_type;
}

Beatmap[] getAllBeatmaps(string apiKey) {
    import apiv1;
    apiv1.Beatmap[] beatmaps;
    // string currentQueryDate = "2007-10-06";
    // string currentQueryDate = "2021-12-30"; // Invalid Max combo
    string currentQueryDate = "2026-09-15 10:00:00";
    enum PAGE_SIZE = 500;
    bool finished = false;
    while (!finished) {
        Beatmap[] response = getBeatmaps(apiKey, since: currentQueryDate, limit: PAGE_SIZE);
        string lastAddedDate = currentQueryDate;
        string lastSeenDate = currentQueryDate;
        size_t lastSeenDateIndex = 0;
        if (response.length < PAGE_SIZE) {
            foreach(beatmap; response) beatmaps ~= beatmap;
            finished = true;
        } else {
            foreach (index, beatmap; response) {
                if (beatmap.approved_date != lastSeenDate) {
                    writefln("new date %s => %s", lastSeenDate, beatmap.approved_date);
                    foreach (b; response[lastSeenDateIndex..index]) {
                        beatmaps ~= b;
                    }
                    lastAddedDate = lastSeenDate;
                    lastSeenDate = beatmap.approved_date;
                    lastSeenDateIndex = index;
                }
            }
        }
        currentQueryDate = lastAddedDate;
        Thread.sleep(dur!"seconds"(1));
    }

    datatypes.Beatmap[] result;

    foreach (b; beatmaps) {
        auto beatmap = b.toBeatmap;
        if (beatmap.isError) {
            writeln(b.beatmap_id, " : ", beatmap.error);
        } else {
            result ~= beatmap.value;
        }
    }
    return result;
}

int main(string[] argv) {
    Settings settings = void;
    parseSettings("settings.ini", settings);

    sqlite3* db;
    scope(exit) sqlite3_close(db);
    if (sqlite3_open("osuw.db", &db)) {
        writefln("Can't open database: %s", sqlite3_errmsg(db).fromStringz());
        return 1;
    }

    createDatabase(db);

    Beatmap[] beatmaps = getAllBeatmaps(settings.apiV1Key);

    foreach (beatmap; beatmaps) {
        insertBeatmap(db, beatmap);
    }

    // Request request = Request();
    // request.addHeaders([
    //     "Accept": "application/json",
    //     "Content-Type": "application/x-www-form-urlencoded",
    // ]);
    // request.keepAlive = false;
    // Response response = request.post(
    //     "https://osu.ppy.sh/oauth/token",
    //     queryParams(
    //         "client_id",     6522, // TODO: parse this from the config file
    //         "client_secret", clientSecret,
    //         "grant_type",    "client_credentials",
    //         "scope",         "public",
    //     ),
    // );

    // JSONValue responseData = parseJSON(response.responseBody.to!string);
    // writeln(deserializeJson!TokenResponse(responseData));
    // getApiV1Beatmaps(settings.apiV1Key);
    return 0;
}
