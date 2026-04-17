import datatypes;

import std.stdio;
import std.string;
import etc.c.sqlite3;

enum DATABASE_VERSION = 1;

/// This also frees the memory associated with the error message
private void printError(char *zErrMsg) {
    scope(exit) sqlite3_free(zErrMsg);
    writefln("SQL error: %s", zErrMsg.fromStringz());
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

sqlite3_stmt* prepareStatementFromString(sqlite3* db, string s) {
    sqlite3_stmt* stmt = null;
    const char* statementSql = s.toStringz();
    if (sqlite3_prepare_v2(db, statementSql, cast(int)s.length + 1, &stmt, null) != SQLITE_OK) {
        throw new Exception(format("Error preparing statement %s", s));
    }
    return stmt;
}

void createDatabase() {
    sqlite3 *db;
    char *zErrMsg = null;
    int rc;

    rc = sqlite3_open("osuw.db", &db);
    scope(exit) sqlite3_close(db);
    if (rc) {
        writefln("Can't open database: %s", sqlite3_errmsg(db).fromStringz());
        return;
    }

    // Stockage de la version de base de données

    rc = sqlite3_exec(db,
        q{ CREATE TABLE IF NOT EXISTS storage(key TEXT PRIMARY KEY, value ANYTHING) },
        &callback, null, &zErrMsg
    );
    if (rc != SQLITE_OK) printError(zErrMsg);

    rc = sqlite3_exec(db, q{ SELECT * FROM storage WHERE key = "version" }, &callback, null, &zErrMsg);
    if (rc != SQLITE_OK) printError(zErrMsg);

    sqlite3_stmt* stmt = prepareStatementFromString(db, q{
        INSERT INTO storage VALUES ("version", @versionValue)
            ON CONFLICT(key) DO UPDATE SET value=excluded.value;
    });

    int versionValueParameterIndex = sqlite3_bind_parameter_index(stmt, "@versionValue".toStringz());
    sqlite3_bind_int(stmt, versionValueParameterIndex, DATABASE_VERSION);
    loop: for (;;) {
        rc = sqlite3_step(stmt);
        switch (rc) {
            case SQLITE_ROW:
                writeln("user_version : ", sqlite3_column_int(stmt, 0));
                break;
            case SQLITE_DONE: break loop;
            default:
                writefln("Error : got unexpected result code %d while executing statment %s\n",
                         rc, sqlite3_expanded_sql(stmt).fromStringz());
                writefln("sqlite3 error : %s", sqlite3_errmsg(db).fromStringz());
                break loop;
        }
    }

    rc = sqlite3_exec(db, q{ SELECT * FROM storage WHERE key = "version" }, &callback, null, &zErrMsg);
    if (rc != SQLITE_OK) printError(zErrMsg);

    // Enregistrement des maps
    // Duration : entier sur 64 bits (nombre de hnsecs)
    // SysTime : convertir avec SysTime.toISOExtString et stocker le string dans une colonne TEXT
    // Ruleset et RankedStatus : convertir en int
    // ObjectCounts : stocker 3 entiers : "hitObjectCount", "holdObjectCount", "bonusObjectCount"
    // liste de mappers : besoin d'une table à mettre à jour en conséquence
    //                    mappers(userId INTEGER, username TEXT, beatmapId INTEGER) STRICT

    auto createBeatmapTableQuery = q{
        CREATE TABLE IF NOT EXISTS beatmaps(
            beatmapId            INTEGER PRIMARY KEY, /* int          beatmapId; */
            beatmapSetId         INTEGER,             /* int          beatmapSetId; */
            rankedStatus         INTEGER,             /* RankedStatus rankedStatus; */
            submittedDate        TEXT,                /* SysTime      submittedDate; */
            rankedDate           TEXT,                /* SysTime      rankedDate; */
            updatedDate          TEXT,                /* SysTime      updatedDate; */
            bpm                  REAL,                /* float        bpm; */
            starRating           REAL,                /* float        starRating; */
            lastStarRatingUpdate TEXT,                /* SysTime      lastStarRatingUpdate; */
            ruleset              INTEGER,             /* Ruleset      ruleset; */
            length               INTEGER,             /* Duration     length; */
            drainLength          INTEGER,             /* Duration     drainLength; */
            difficultyName       TEXT,                /* string       difficultyName; */
            hitObjectCount       INTEGER,             /* ObjectCounts objectCounts; */
            holdObjectCount      INTEGER,
            bonusObjectCount     INTEGER,
            maxCombo             INTEGER              /* int          maxCombo; */
        ) STRICT;
    }.toStringz();

    rc = sqlite3_exec(db, createBeatmapTableQuery, &callback, null, &zErrMsg);
    if (rc != SQLITE_OK) printError(zErrMsg);

    auto createMapperTableQuery = q{
        CREATE TABLE IF NOT EXISTS mapperBeatmaps(
            userId    INTEGER,
            username  TEXT,
            beatmapId INTEGER
        ) STRICT;
    }.toStringz();

    rc = sqlite3_exec(db, createMapperTableQuery, &callback, null, &zErrMsg);
    if (rc != SQLITE_OK) printError(zErrMsg);
}

void insertBeatmap(sqlite3* db, Beatmap beatmap) {

    // TODO: Terminer ce truc
    enum query = {
        string query = q{
            INSERT INTO beatmaps VALUES (
        };

        static foreach(index, member; __traits(allMembers, Beatmap)) {
            static if (member != "objectCounts") {
                query ~= "@" ~ member ~ ",";
            }
        }

        query ~= q{
            ) ON CONFLICT(key) DO UPDATE SET value=excluded.value;
        };
        return query;
    }();

    sqlite3_stmt* stmt = prepareStatementFromString(db, query);

    /+
    beatmapId            INTEGER PRIMARY KEY, /* int          beatmapId; */
    beatmapSetId         INTEGER,             /* int          beatmapSetId; */
    rankedStatus         INTEGER,             /* RankedStatus rankedStatus; */
    submittedDate        TEXT,                /* SysTime      submittedDate; */
    rankedDate           TEXT,                /* SysTime      rankedDate; */
    updatedDate          TEXT,                /* SysTime      updatedDate; */
    bpm                  REAL,                /* float        bpm; */
    starRating           REAL,                /* float        starRating; */
    lastStarRatingUpdate TEXT,                /* SysTime      lastStarRatingUpdate; */
    ruleset              INTEGER,             /* Ruleset      ruleset; */
    length               INTEGER,             /* Duration     length; */
    drainLength          INTEGER,             /* Duration     drainLength; */
    difficultyName       TEXT,                /* string       difficultyName; */
    hitObjectCount       INTEGER,             /* ObjectCounts objectCounts; */
    holdObjectCount      INTEGER,
    bonusObjectCount     INTEGER,
    maxCombo             INTEGER              /* int          maxCombo; */
    +/
}
