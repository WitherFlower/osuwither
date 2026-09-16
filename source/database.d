import datatypes;

import std.algorithm;
import std.array;
import std.sumtype : match;
import std.stdio;
import std.string;
import std.typecons;
import etc.c.sqlite3;

enum DATABASE_VERSION = 1;

// TODO: (Code Quality) Use this everywhere
// TODO: (Reliability) Test this against the database when starting the app
enum string[] beatmapTableFields = [
    "beatmapId",
    "beatmapSetId",
    "rankedStatus",
    "submittedDate",
    "rankedDate",
    "updatedDate",
    "bpm",
    "starRating",
    "lastStarRatingUpdate",
    "ruleset",
    "length",
    "drainLength",
    "difficultyName",
    "hitObjectCount",
    "holdObjectCount",
    "bonusObjectCount",
    "maxCombo"
];

private int[string] beatmapTableFieldIndexes;

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
        throw new Exception(format("Error preparing statement :\n%s\n\nError Message :\n%s",
                                   s, sqlite3_errmsg(db).fromStringz()));
    }
    return stmt;
}

void createDatabase(sqlite3* db) {
    char* zErrMsg = null;
    int rc;

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
    // Duration : nombre de secondes
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

    // Create Mapper Table

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
    enum insertBeatmapQuery = {
        string query = q{
            INSERT OR REPLACE INTO beatmaps(
        };

        query ~= beatmapTableFields.join(",");

        query ~= q{
            ) VALUES (
        };

        query ~= beatmapTableFields.map!(s => "@" ~ s).join(",");

        query ~= q{
            );
        };
        return query;
    }();

    sqlite3_stmt* insertBeatmapStmt = prepareStatementFromString(db, insertBeatmapQuery);
    scope(exit) sqlite3_finalize(insertBeatmapStmt);

    beatmapTableFieldIndexes = beatmapTableFields.map!((fieldName) {
        string parameterName = "@" ~ fieldName;
        return tuple(fieldName, sqlite3_bind_parameter_index(insertBeatmapStmt, parameterName.toStringz()));
    }).assocArray;

    foreach (field; beatmapTableFields) {
        int indexInQuery = beatmapTableFieldIndexes[field];
        final switch (field) {
            case "beatmapId":
                sqlite3_bind_int(insertBeatmapStmt, indexInQuery, beatmap.beatmapId);
                break;
            case "beatmapSetId":
                sqlite3_bind_int(insertBeatmapStmt, indexInQuery, beatmap.beatmapSetId);
                break;
            case "rankedStatus":
                sqlite3_bind_int(insertBeatmapStmt, indexInQuery, beatmap.rankedStatus);
                break;
            case "submittedDate":
                string submittedDate = beatmap.submittedDate.toISOExtString();
                sqlite3_bind_text(
                    insertBeatmapStmt, indexInQuery,
                    submittedDate.ptr, cast(int)submittedDate.length,
                    SQLITE_TRANSIENT
                );
                break;
            case "rankedDate":
                string rankedDate = beatmap.rankedDate.toISOExtString();
                sqlite3_bind_text(
                    insertBeatmapStmt, indexInQuery,
                    rankedDate.ptr, cast(int)rankedDate.length,
                    SQLITE_TRANSIENT
                );
                break;
            case "updatedDate":
                string updatedDate = beatmap.updatedDate.toISOExtString();
                sqlite3_bind_text(
                    insertBeatmapStmt, indexInQuery,
                    updatedDate.ptr, cast(int)updatedDate.length,
                    SQLITE_TRANSIENT
                );
                break;
            case "bpm":
                sqlite3_bind_double(insertBeatmapStmt, indexInQuery, beatmap.bpm);
                break;
            case "starRating":
                sqlite3_bind_double(insertBeatmapStmt, indexInQuery, beatmap.starRating);
                break;
            case "lastStarRatingUpdate":
                string lastStarRatingUpdateDate = beatmap.lastStarRatingUpdate.toISOExtString();
                sqlite3_bind_text(
                    insertBeatmapStmt, indexInQuery,
                    lastStarRatingUpdateDate.ptr, cast(int)lastStarRatingUpdateDate.length,
                    SQLITE_TRANSIENT
                );
                break;
            case "ruleset":
                sqlite3_bind_int(insertBeatmapStmt, indexInQuery, beatmap.ruleset);
                break;
            case "length":
                sqlite3_bind_int64(insertBeatmapStmt, indexInQuery, beatmap.length.total!"seconds");
                break;
            case "drainLength":
                sqlite3_bind_int64(insertBeatmapStmt, indexInQuery, beatmap.drainLength.total!"seconds");
                break;
            case "difficultyName":
                sqlite3_bind_text(
                    insertBeatmapStmt, indexInQuery,
                    beatmap.difficultyName.ptr, cast(int)beatmap.difficultyName.length,
                    SQLITE_TRANSIENT
                );
                break;
            case "hitObjectCount":
                sqlite3_bind_int(insertBeatmapStmt, indexInQuery, beatmap.objectCounts.match!(
                    (OsuObjectCounts   o) => o.circleCount,
                    (TaikoObjectCounts o) => o.hitCount,
                    (CatchObjectCounts o) => o.fruitCount,
                    (ManiaObjectCounts o) => o.noteCount,
                ));
                break;
            case "holdObjectCount":
                sqlite3_bind_int(insertBeatmapStmt, indexInQuery, beatmap.objectCounts.match!(
                    (OsuObjectCounts   o) => o.sliderCount,
                    (TaikoObjectCounts o) => o.drumrollCount,
                    (CatchObjectCounts o) => o.juiceCount,
                    (ManiaObjectCounts o) => o.holdNoteCount,
                ));
                break;
            case "bonusObjectCount":
                sqlite3_bind_int(insertBeatmapStmt, indexInQuery, beatmap.objectCounts.match!(
                    (OsuObjectCounts   o) => o.spinnerCount,
                    (TaikoObjectCounts o) => o.swellCount,
                    (CatchObjectCounts o) => o.bananaCount,
                    (ManiaObjectCounts _) => 0,
                ));
                break;
            case "maxCombo":
                sqlite3_bind_int(insertBeatmapStmt, indexInQuery, beatmap.maxCombo);
                break;
        }
    }

    loop: for (int i = 0; ; i++) {
        int rc = sqlite3_step(insertBeatmapStmt);
        switch (rc) {
            case SQLITE_ROW:
                writefln("%d: %d", i, sqlite3_column_int(insertBeatmapStmt, 0));
                break;
            case SQLITE_DONE: break loop;
            default:
                writefln("Error : got unexpected result code %d while executing statment %s\n",
                         rc, sqlite3_expanded_sql(insertBeatmapStmt).fromStringz());
                writefln("sqlite3 error : %s", sqlite3_errmsg(db).fromStringz());
                break loop;
        }
    }
}
