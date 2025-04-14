-- VOTV integration v0.0.0
-- Copyright (C) 2025  Nikita Podvirnyi <krypt0nn@vk.com>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

type Variant = {
    platform: string,
    edition: string
}

type Version = {
    version: string,
    title: string,
    url: string
}

local data_dir_path = path.persist_dir("voices_of_the_void")

local settings_file_path = path.join(data_dir_path, "settings.json")

local game_dir_path     = path.join(data_dir_path, "game")
local game_version_path = path.join(game_dir_path, ".version")
local game_binary_path  = path.join(game_dir_path, "VotV.exe")

------------------------------------------------- Imports -------------------------------------------------

local function import_components()
    return import("components").components("voices_of_the_void")
end

------------------------------------------------- Game versions -------------------------------------------------

-- Direct download links are taken from here: https://archive.org/details/votv-archive
local game_versions = {
    { version = "pa0082_0012", title = "Pre-Alpha 0.8.2b", url = "https://archive.org/download/votv-archive/pa0082_0012.7z" },
    { version = "pa0081_0008", title = "Pre-Alpha 0.8.1",  url = "https://archive.org/download/votv-archive/pa0081_0008.7z" },
    { version = "pa08_0017",   title = "Pre-Alpha 0.8.0",  url = "https://archive.org/download/votv-archive/pa08_0017.7z" },
    { version = "pa07_0011",   title = "Pre-Alpha 0.7.0",  url = "https://archive.org/download/votv-archive/pa07_0011.7z" }
}

local function last_game_version(): Version
    local iter = import("iterable")

    return iter(game_versions).cloned().first()
end

------------------------------------------------- Settings -------------------------------------------------

type Settings = {
    game_version: string
}

local function get_settings()
    if not path.exists(settings_file_path) then
        fs.write_file(settings_file_path, "{}")
    end

    local settings = str.decode(str.from_bytes(fs.read_file(settings_file_path)), "json")

    local iter = import("iterable")

    local valid_version = iter(game_versions).cloned()
        .any(function(info) return info.version == settings.game_version end)

    if not settings.game_version or not valid_version then
        settings.game_version = last_game_version().version
    end

    return settings
end

local function set_settings(settings: Settings)
    fs.write_file(settings_file_path, str.encode(settings, "json"))
end

------------------------------------------------- Game -------------------------------------------------

local function get_game_version(): Version | nil
    if not fs.exists(game_version_path) then
        return nil
    end

    local iter = import("iterable")

    local version = str.from_bytes(fs.read_file(game_version_path))

    for _, info in iter(game_versions).cloned() do
        if version == info.version then
            return info
        end
    end

    return nil
end

local function set_game_version(version: string)
    fs.write_file(game_version_path, str.to_bytes(version))
end

local function is_game_installed(): boolean
    local version = get_game_version()

    if not version then
        return false
    end

    local settings = get_settings()

    return version.version == settings.game_version
end

------------------------------------------------- Module -------------------------------------------------

return {
    standard = 1,

    editions = function(platform: string)
        local i18n = import("i18n").i18n

        return {
            {
                name = "default",
                title = i18n("default_game_edition")
            }
        }
    end,

    game = {
        get_status = function(variant: Variant)
            local status = import_components().game.get_status(variant)

            if status then
                return status
            end

            if not is_game_installed() then
                return "not-installed"
            end

            return "installed"
        end,

        get_diff = function(variant: Variant)
            local diff = import_components().game.get_diff(variant)

            if diff then
                return diff
            end

            if is_game_installed() then
                return nil
            end

            local i18n = import("i18n").i18n

            local info = last_game_version()

            local archive_path = path.join(path.temp_dir(), `votv_{info.version}.7z`)

            return {
                title = i18n("install_game"),

                pipeline = {
                    {
                        title = i18n("delete_old_files"),

                        before = function()
                            return fs.exists(game_dir_path)
                        end,

                        perform = function()
                            fs.remove_dir(game_dir_path)
                        end
                    },

                    {
                        title = i18n("download_game_files"),

                        perform = function(updater)
                            downloader.download(info.url, {
                                output_file = archive_path,
                                continue_downloading = true,

                                progress = function(current, total, diff)
                                    updater({
                                        progress = {
                                            current = current,
                                            total = total,

                                            format = function()
                                                local current = current / 1000 / 1000 / 1000
                                                local total = total / 1000 / 1000 / 1000

                                                return i18n("downloading_progress", {
                                                    current = math.floor(current * 100) / 100,
                                                    total = math.floor(total * 100) / 100
                                                })
                                            end
                                        }
                                    })
                                end
                            })
                        end
                    },

                    {
                        title = i18n("extract_game_files"),

                        perform = function(updater)
                            local handle = archive.open(archive_path)

                            archive.extract(handle, data_path, function(current, total, diff)
                                updater({
                                    progress = {
                                        current = current,
                                        total = total,

                                        format = function()
                                            local current = current / 1000 / 1000 / 1000
                                            local total = total / 1000 / 1000 / 1000

                                            return i18n("extraction_progress", {
                                                current = math.floor(current * 100) / 100,
                                                total = math.floor(total * 100) / 100
                                            })
                                        end
                                    }
                                })
                            end)

                            archive.close(handle)

                            fs.move(path.join(data_path, info.version, "WindowsNoEditor"), game_dir_path)
                            fs.remove(path.join(data_path, info.version))
                            fs.remove(archive_path)

                            set_game_version(info.version)
                        end
                    }
                }
            }
        end,

        get_launch_info = function(variant: Variant)
            if not is_game_installed() then
                return {
                    status = "disabled",
                    binary = game_binary_path
                }
            end

            return import_components().game.wrap_launch_info({
                status = "normal",
                binary = game_binary_path
            })
        end
    },

    settings = {
        get_property = function(name: string)
            local value = import_components().settings.get_property(name)

            if value then
                return value
            end

            local settings = get_settings()

            return settings[name]
        end,

        set_property = function(name: string, value: any)
            local result = import_components().settings.set_property(name, value)

            if not result then
                local settings = get_settings()

                settings[name] = value

                set_settings(settings)
            end
        end,

        get_layout = function(variant: Variant)
            local iter = import("iterable")
            local i18n = import("i18n").i18n

            local settings = get_settings()

            local layout = {
                {
                    title = i18n("game"),

                    entries = {
                        {
                            name = "game_version",
                            title = i18n("game_version"),

                            entry = {
                                format = "enum",

                                values = iter(game_versions)
                                    .cloned()
                                    .fold({}, function(values, info)
                                        values[info.version] = info.title

                                        return values
                                    end),

                                selected = settings.game_version
                            }
                        }
                    }
                }
            }

            return iter(layout)
                .chain(import_components().settings.get_layout())
                .collect()
        end
    }
}
