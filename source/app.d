import std.stdio;
import std.string;
import std.json;
import std.conv;
import std.sumtype;
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

void createDatabase() {
    sqlite3 *db;
    char *zErrMsg = null;
    int rc;

    rc = sqlite3_open("osuw.db", &db);
    if (rc) {
        writeln("Can't open database: ", sqlite3_errmsg(db));
        sqlite3_close(db);
        return;
    }
    rc = sqlite3_exec(db, "CREATE TABLE user(id, name)", &callback, null, &zErrMsg);
    if (rc != SQLITE_OK) {
        writeln("SQL error: ", zErrMsg);
        sqlite3_free(zErrMsg);
    }
    sqlite3_close(db);
}

struct TokenResponse {
    int expires_in;
    string access_token;
    string token_type;
}

// TODO: This will probably break if you add member functions to the deserialized struct
T deserializeJson(T)(JSONValue json) {
    T result;
    foreach (string member; __traits(allMembers, T)) {
        __traits(getMember, result, member) = json[member].get!(
            typeof(__traits(getMember, result, member))
        );
    }
    return result;
}

void getApiV1Beatmaps(string key) {
    Request request = Request();
    request.addHeaders([
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
    ]);
    request.keepAlive = false;
    request.verbosity = 2;
    Response response = request.post(
        "https://osu.ppy.sh/api/get_beatmaps",
        queryParams(
            "k",     key,
            "limit", 500,
        ),
    );
    writeln(response.responseBody);
}

int main(string[] argv) {
    Settings settings = void;
    parseSettings("settings.ini", settings);

    Request request = Request();
    request.addHeaders([
        "Accept": "application/json",
        "Content-Type": "application/x-www-form-urlencoded",
    ]);
    request.keepAlive = false;
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
    getApiV1Beatmaps(settings.apiV1Key);

    return 0;
}
