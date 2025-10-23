module deserialize;

import std.conv;
import std.json;
import std.stdio;
import std.traits;

bool isJsonGettable(T)() {
    return is(immutable T == immutable string)
        || is(immutable T == immutable bool)
        || isFloatingPoint!T
        || isIntegral!T;
}

bool deserializeJson(T)(JSONValue json, out T result, ref string error)
if (isDynamicArray!T) {
    foreach (index, JSONValue jsonElement; json.array) {
        alias ElementType = typeof(result[0]);
        static if (isJsonGettable!ElementType) {
            try {
                result ~= jsonElement.get!ElementType;
            } catch (Exception e) {
                error ~= "Could not deserialize value at index "
                      ~  index.to!string();
                return false;
            }
        } else {
            ElementType element = void;
            if (!jsonElement.deserializeJson(element, error)) {
                error ~= "\n    in value at index "
                      ~  index.to!string();
                return false;
            }
            result ~= element;
        }
    }
    return true;
}

struct AliasOf {
    string aliasedName;
}

bool deserializeJson(T)(JSONValue json, out T result, ref string error)
if (is(T == struct)) {
    foreach (string memberName; __traits(allMembers, T)) {
        alias MemberType = typeof(__traits(getMember, result, memberName));
        string lookupName = memberName;

        // Check struct member attributes for @AliasOf("other_name")
        // If we find that, set lookupName to some other name and lookup that name
        // in the json value we are trying to parse
        alias attributes = __traits(getAttributes, __traits(getMember, result, memberName));
        enum aliasing = attributes.length > 0 && is(typeof(attributes[0]) == AliasOf);
        static if (aliasing) { lookupName = attributes[0].aliasedName; }

        if (!(lookupName in json)) {
            error ~= "Could not find key \"" ~ lookupName ~ "\"";
            return false;
        }
        static if (isJsonGettable!MemberType) {
            try {
                // Check if the null literal converts to type MemberType
                // https://forum.dlang.org/post/gzxulzoyjzlprhvobktx@forum.dlang.org
                static if (is(typeof(null) : MemberType)) {
                    // In that case, handle the case where the json contains a null value
                    if (json[lookupName].isNull) {
                        __traits(getMember, result, memberName) = null;
                        continue;
                    }
                }
                __traits(getMember, result, memberName) = json[lookupName].get!MemberType;
            } catch (Exception e) {
                error ~= "Could not deserialize value with key \"" ~ lookupName ~ "\"";
                return false;
            }
        } else {
            MemberType member = void;
            if (!deserializeJson!MemberType(json[lookupName], member, error)) {
                error ~= "\n    in value of key \"" ~ lookupName ~ "\"";
                return false;
            }
            __traits(getMember, result, memberName) = member;
        }
    }
    return true;
}

struct Thing { int[] a; string b; Foo f; }
struct Foo { string bar; }

void test() {

    JSONValue json = `{"a": [42, 69], "b": "Bonswag", "f": {"bar": "nested"}}`.parseJSON();
    string error = "";
    Thing t = void;
    if (!json.deserializeJson(t, error))
        writeln(error);
    else
        writeln(t);

    JSONValue badJson = `{"a": [42, 69], "b": "Bonswag", "f": {"bad_key": "nested"}}`.parseJSON();
    error = "";
    Thing t2 = void;
    if (!badJson.deserializeJson(t2, error))
        writeln(error);
    else
        writeln(t2);

    JSONValue json2 = `{ "bar": "asdf" }`.parseJSON();
    error = "";
    Foo f = void;
    if (!json2.deserializeJson(f, error))
        writeln(error);
    else
        writeln(f);

    JSONValue jsonArr = `[1, 42, "69", 1337, 80085]`.parseJSON();
    error = "";
    int[] intArray = void;
    if (!jsonArr.deserializeJson(intArray, error))
        writeln(error);
    else
        writeln(intArray);
}
