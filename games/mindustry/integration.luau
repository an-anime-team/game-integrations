-- Mindustry integration v0.0.0
-- Copyright (C) 2026  Dylan Donnell <greenicedtea@tutanota.com>
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

--!nocheck

function import(...)
    return (load("import").value)(...)
end

type Variant = {
    platform: string,
    edition: string
}

type Version = {
    version: string,
    title: string,
    url: string
}

local data_dir_path: string = path.persist_dir("mindustry")

local game_dir_path: string = path.join(data_dir_path, "game")
local game_version_path: string = path.join(game_dir_path, ".version")
local game_jar_path: string = path.join(game_dir_path, "Mindustry.jar")

local jre_dir_path: string = path.join(data_dir_path, "jre")
local jre_binary_path: string = path.join(jre_dir_path, "bin", "java")

local jre_url: string = "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jre/hotspot/normal/eclipse"

------------------------------------------------- Game versions -------------------------------------------------

local function list_versions()
    return {
        { version = "157.4", title = "v157.4", url = "https://github.com/Anuken/Mindustry/releases/download/v157.4/Mindustry.jar" },
        { version = "157.3", title = "v157.3", url = "https://github.com/Anuken/Mindustry/releases/download/v157.3/Mindustry.jar" },
        { version = "157.2", title = "v157.2", url = "https://github.com/Anuken/Mindustry/releases/download/v157.2/Mindustry.jar" },
        { version = "157.1", title = "v157.1", url = "https://github.com/Anuken/Mindustry/releases/download/v157.1/Mindustry.jar" },
        { version = "157",   title = "v157",   url = "https://github.com/Anuken/Mindustry/releases/download/v157/Mindustry.jar"   },
        { version = "156.2", title = "v156.2", url = "https://github.com/Anuken/Mindustry/releases/download/v156.2/Mindustry.jar" },
        { version = "156.1", title = "v156.1", url = "https://github.com/Anuken/Mindustry/releases/download/v156.1/Mindustry.jar" },
        { version = "156",   title = "v156",   url = "https://github.com/Anuken/Mindustry/releases/download/v156/Mindustry.jar"   },
        { version = "155.4", title = "v155.4", url = "https://github.com/Anuken/Mindustry/releases/download/v155.4/Mindustry.jar" },
        { version = "155.3", title = "v155.3", url = "https://github.com/Anuken/Mindustry/releases/download/v155.3/Mindustry.jar" },
    }
end

local function last_version(): Version
    local iter = import("iterable")

    return iter(list_versions()).first()
end

local function get_version_info(version: string): Version?
    local iter = import("iterable")

    return iter(list_versions())
        .find(function(info) return info.version == version end)
end

------------------------------------------------- Settings -------------------------------------------------

local __settings = nil

local function import_settings()
    if not __settings then
        local iter = import("iterable")
        local i18n = import("i18n").i18n()

        __settings = import("settings")({
            game = "mindustry",
            layout = {
                game = {
                    title = i18n("game"),
                    entries = {
                        version = {
                            title = i18n("game_version"),
                            entry = {
                                format = "enum",

                                values = iter(list_versions())
                                    .fold({}, function(values, info)
                                        values[info.version] = info.title

                                        return values
                                    end),

                                default = last_version().version
                            }
                        }
                    }
                }
            }
        })
    end

    return __settings
end

------------------------------------------------- JRE -------------------------------------------------

local function is_jre_installed(): boolean
    return fs.exists(jre_binary_path)
end

------------------------------------------------- Game state -------------------------------------------------

local function get_game_version(): string?
    if not fs.exists(game_version_path) then
        return nil
    end

    return str.from_bytes(fs.read_file(game_version_path):await())
end

local function set_game_version(version: string)
    fs.write_file(game_version_path, str.to_bytes(version)):await()
end

local function is_game_installed(): boolean
    local version = get_game_version()

    if not version then
        return false
    end

    local settings = import_settings()

    return version == settings.get_property("game.version")
end

------------------------------------------------- Module -------------------------------------------------

return function()
    return {
        game = {
            get_launch_info = function(variant: Variant)
                if not is_game_installed() or not is_jre_installed() then
                    return nil
                end

                return {
                    binary = jre_binary_path,
                    args = { "-jar", game_jar_path }
                }
            end,

            get_actions_pipeline = function(variant: Variant)
                local settings = import_settings()

                if is_game_installed() and is_jre_installed() then
                    return nil
                end

                local selected_version = settings.get_property("game.version")

                local info = get_version_info(selected_version)

                if not info then
                    error(`invalid game version selected: {selected_version}`)
                end

                local i18n = import("i18n").i18n()

                local pipeline = {}

                if not is_jre_installed() then
                    local jre_archive_path: string = path.join(path.temp_dir(), "mindustry_jre.tar.gz")
                    local jre_staging_path: string = path.join(data_dir_path, ".jre_staging")

                    table.insert(pipeline, {
                        title = "Install Java Runtime",

                        perform = function(updater)
                            local downloader_handle = downloader.create()

                            local task_handle = downloader.download(downloader_handle, {
                                url = jre_url,
                                output_file = jre_archive_path,
                                continue_download = true,

                                on_update = function(current: number, total: number)
                                    updater({
                                        current = current,
                                        total = total,

                                        format = function()
                                            local current = current / 1000 / 1000
                                            local total = total / 1000 / 1000

                                            return i18n("downloading_progress_mb", {
                                                current = math.floor(current * 100) / 100,
                                                total = math.floor(total * 100) / 100
                                            })
                                        end
                                    })
                                end
                            })

                            downloader.wait(task_handle)
                            downloader.close(downloader_handle)

                            if not fs.exists(jre_staging_path) then
                                fs.create_dir(jre_staging_path):await()
                            end

                            local handle: number = archive.open(jre_archive_path)

                            archive.extract(handle, jre_staging_path, function(current: number, total: number)
                                updater({
                                    current = current,
                                    total = total,

                                    format = function()
                                        local current = current / 1000 / 1000
                                        local total = total / 1000 / 1000

                                        return i18n("extracting_progress_mb", {
                                            current = math.floor(current * 100) / 100,
                                            total = math.floor(total * 100) / 100
                                        })
                                    end
                                })
                            end)

                            archive.close(handle)

                            for _, entry in fs.read_dir(jre_staging_path):await() do
                                if entry.type == "directory" then
                                    fs.move(entry.path, jre_dir_path):await()
                                    break
                                end
                            end

                            fs.remove_dir(jre_staging_path):await()
                            fs.remove(jre_archive_path):await()
                        end
                    })
                end

                table.insert(pipeline, {
                    title = i18n("delete_unused_game_files_title"),

                    before = function()
                        return fs.exists(game_dir_path)
                    end,

                    perform = function()
                        fs.remove_dir(game_dir_path):await()
                    end
                })

                table.insert(pipeline, {
                    title = i18n("download_game_files_title"),

                    perform = function(updater)
                        if not fs.exists(game_dir_path) then
                            fs.create_dir(game_dir_path):await()
                        end

                        local downloader_handle = downloader.create()

                        local task_handle = downloader.download(downloader_handle, {
                            url = info.url,
                            output_file = game_jar_path,
                            continue_download = true,

                            on_update = function(current: number, total: number)
                                updater({
                                    current = current,
                                    total = total,

                                    format = function()
                                        local current = current / 1000 / 1000
                                        local total = total / 1000 / 1000

                                        return i18n("downloading_progress_mb", {
                                            current = math.floor(current * 100) / 100,
                                            total = math.floor(total * 100) / 100
                                        })
                                    end
                                })
                            end
                        })

                        downloader.wait(task_handle)
                        downloader.close(downloader_handle)

                        set_game_version(info.version)
                    end
                })

                return {
                    title = i18n("install_game_title"),
                    pipeline = pipeline
                }
            end,
        },

        settings = {
            get_property = function(name: string): any
                local settings = import_settings()

                return settings.get_property(name)
            end,

            set_property = function(name: string, value: any)
                local settings = import_settings()

                settings.set_property(name, value)
            end,

            get_layout = function(variant: Variant)
                local settings = import_settings()

                return settings.get_layout(variant)
            end
        }
    }
end
