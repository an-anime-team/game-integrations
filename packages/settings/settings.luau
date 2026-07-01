-- settings v0.2.0
-- Copyright (C) 2025 - 2026  Nikita Podvirnyi <krypt0nn@vk.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the “Software”), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

--!nocheck

type Localizable = string | { [string]: string }

----------------------------- builder layout types -----------------------------

type EntryReactivity = "none" | "relaxed" | "release"

type EntryFormatName =
    | "switch"
    | "text"
    | "secret_text"
    | "enum"
    | "selector"
    | "expandable"

type BuilderEntryOptions = {
    -- Call this function before returning settings value.
    get: ((value: any) -> any)?;

    -- Call this function before updating settings value.
    set: ((value: any) -> any)?;
}

type BuilderOptions = {
    game: string,
    layout: {BuilderGroupLayout}
}

type BuilderGroupLayout = {
    name: string;
    title: Localizable?;
    description: Localizable?;
    entries: {BuilderEntryLayout};
}

type BuilderEntryLayout = {
    name: string;
    title: Localizable,
    description: Localizable?,
    reactivity: EntryReactivity?,

    entry: {
        format: EntryFormatName,
        default: any,

        -- enum / selector
        values: {{ name: string, title: Localizable }}?,

        -- expandable
        entries: {BuilderEntryLayout}?
    },

    options: BuilderEntryOptions?
}

----------------------------- actual layout types -----------------------------

type GroupLayout = {
    title: Localizable?,
    description: Localizable?,
    entries: {EntryLayout}
}

type EntryLayout = {
    name: string?,
    title: Localizable,
    description: Localizable?,
    reactivity: EntryReactivity?,
    entry: {EntryFormat}
}

type EntryFormat =
    | EntryFormatSwitch
    | EntryFormatText
    | EntryFormatEnum
    | EntryFormatExpandable

type EntryFormatSwitch = {
    format: "switch",
    value: string
}

type EntryFormatText = {
    format: "text",
    value: string
}

type EntryFormatSecretText = {
    format: "secret_text",
    value: string
}

type EntryFormatEnum = {
    format: "enum",
    values: {{ name: string, title: Localizable }},
    selected: string
}

type EntryFormatSelector = {
    format: "selector",
    values: {{ name: string, title: Localizable }},
    selected: string
}

type EntryFormatExpandable = {
    format: "expandable",
    entries: {EntryFormat}
}

----------------------------- module -----------------------------

local function serialize(value: any): string?
    if typeof(value) == "string" then
        return `s:{value}`
    elseif typeof(value) == "number" then
        return `n:{value}`
    elseif typeof(value) == "boolean" then
        return if value then "b:1" else "b:0"
    elseif typeof(value) == "table" then
        return `o:{str.encode("bson", value)}`
    else
        return nil
    end
end

local function deserialize(value: string): any
    if not value then
        return nil
    end

    local format, value = string.match(value, "^([snbo]):(.*)$")

    if format == "s" then
        return value
    elseif format == "n" then
        return tonumber(value)
    elseif format == "b" then
        return value == "1"
    elseif format == "o" then
        return str.decode("bson", value)
    else
        return nil
    end
end

local settings_path: string = path.join(path.persist_dir("settings"), "settings.db")
local settings_handle: number = sqlite.open(settings_path)

sqlite.batch(settings_handle, [[
    CREATE TABLE IF NOT EXISTS settings (
        game  TEXT NOT NULL,
        key   TEXT NOT NULL,
        value TEXT NOT NULL,

        PRIMARY KEY (game, key)
    );

    PRAGMA optimize;
]]):await()

local function get_raw_property(game: string, key: string): any
    local value: { string }? = sqlite.query_row(
        settings_handle,
        "SELECT value FROM settings WHERE game = ?1 AND key = ?2",
        { game, key }
    ):await()

    if not value then
        return nil
    else
        return deserialize(value[1])
    end
end

local function set_raw_property(game: string, key: string, value: any)
    value = serialize(value)

    if not value then
        sqlite.exec(
            settings_handle,
            "DELETE FROM settings WHERE game = ?1 AND key = ?2",
            { game, key }
        ):await()
    else
        sqlite.exec(
            settings_handle,
            "INSERT OR REPLACE INTO settings (game, key, value) VALUES (?1, ?2, ?3)",
            { game, key, value }
        ):await()
    end
end

return function(options: BuilderOptions)
    local entries = {}

    if not options or not options.game then
        error("settings module must get the game name")
    end

    for group_name: string | number, group in pairs(options.layout) do
        if typeof(group.name) == "string" then
            group_name = group.name or group.key
        end

        if typeof(group_name) ~= "string" then
            error("settings module got invalid group name")
        end

        if typeof(group) ~= "table" then
            error("settings module got invalid group info")
        end

        for entry_name: string | number, entry in pairs(group.entries) do
            if typeof(entry.name) == "string" then
                entry_name = entry.name or entry.key
            end

            if typeof(entry_name) ~= "string" then
                error(`settings module got invalid group "{group_name}" entry name for game "{options.game}"`)
            end

            if typeof(entry) ~= "table" then
                error(`settings module got invalid group "{group_name}" entry info for game "{options.game}"`)
            end

            local key = `{group_name}.{entry_name}`

            local entry_options = entry.options or {}

            entries[key] = {
                key = key,
                get = entry_options.get or nil,
                set = entry_options.set or nil,
                default = entry.entry.default
            }
        end
    end

    local function get_property(key: string): any
        local value = get_raw_property(options.game, key)

        if entries[key] then
            if entries[key].get then
                value = entries[key].get(value)
            end

            if entries[key].default ~= nil and value == nil then
                value = entries[key].default
            end
        end

        return value
    end

    local function set_property(key: string, value: any)
        if entries[key] and entries[key].set then
            value = entries[key].set(value)
        end

        set_raw_property(options.game, key, value)
    end

    return {
        get_property = get_property,
        set_property = set_property,

        get_layout = function(): {GroupLayout}
            local layout = {}

            for group_name: string | number, group in pairs(options.layout) do
                if typeof(group.name) == "string" then
                    group_name = group.name or group.key
                end

                local group_layout: GroupLayout = {
                    title = group.title,
                    description = group.description,
                    entries = {}
                }

                for entry_name: string | number, entry in pairs(group.entries) do
                    if typeof(entry.name) == "string" then
                        entry_name = entry.name or entry.key
                    end

                    local key = `{group_name}.{entry_name}`

                    local value = get_property(key)

                    entry.entry["value"] = value
                    entry.entry["selected"] = value

                    table.insert(group_layout.entries, {
                        name = key,
                        title = entry.title,
                        description = entry.description,
                        reactivity = entry.reactivity,
                        entry = entry.entry
                    } :: EntryLayout)
                end

                table.insert(layout, group_layout)
            end

            return layout
        end
    }
end
