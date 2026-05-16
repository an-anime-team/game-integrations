-- Mindustry integration v0.0.0
-- Copyright (C) 2026  Dylan Donnell <greenicedtea@tutanota.com>,
--                     Nikita Podvirnyi <krypt0nn@vk.com>
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

type GameVariant = {
    platform: string,
    edition: string
}

local data_dir_path: string = path.persist_dir("mindustry")

local jre_dir_path: string = path.join(data_dir_path, "jre")
local jre_binary_path: string = path.join(jre_dir_path, "bin", "java")
local jre_version_path: string = path.join(data_dir_path, ".version")

local game_dir_path: string = path.join(data_dir_path, "game")
local game_jar_path: string = path.join(game_dir_path, "Mindustry.jar")
local game_version_path: string = path.join(game_dir_path, ".version")

----------------------------- Imports -----------------------------

__i18n = nil

local function i18n(...)
    if not __i18n then
        local locales = import("locales-src")

        locales = fs.read_file(locales):await()
        locales = str.decode("toml", str.from_bytes(locales))

        __i18n = import("i18n").i18n(locales)
    end

    return (__i18n)(...)
end

----------------------------- JRE and game info -----------------------------

local __versions = nil

type RemoteJreInfo = {
    title: string,
    version: string,
    name: string,
    hash: string,
    url: string
}

-- Read JRE info from the integration's versions.json file
local function get_remote_jre_info(): JreInfo
    if not __versions then
        local versions_src = import("versions-src")

        __versions = fs.read_file(versions_src):await()
        __versions = str.decode("json", str.from_bytes(__versions))
    end

    if not __versions or not __versions["jre"] then
        error("JRE version info is missing")
    end

    return clone(__versions["jre"])
end

-- Read currently installed JRE version, or nil if JRE is not installed
local function get_current_jre_version(): string | nil
    if not fs.exists(jre_version_path) then
        return nil
    end

    local version = fs.read_file(jre_version_path):await()

    return str.from_bytes(version)
end

-- Write version string to the JRE version file
local function set_current_jre_version(version: string)
    if not fs.exists(jre_dir_path) then
        fs.create_dir(jre_dir_path):await()
    end

    fs.write_file(jre_version_path, version):await()
end

type RemoteGameInfo = {
    version: string,
    hash: string,
    url: string
}

-- Read game versions info from the integration's versions.json file
local function list_remote_game_versions(): { RemoteGameInfo }
    if not __versions then
        local versions_src = import("versions-src")

        __versions = fs.read_file(versions_src):await()
        __versions = str.decode("json", str.from_bytes(__versions))
    end

    if not __versions or not __versions["game"] then
        error("game versions info is missing")
    end

    return clone(__versions["game"])
end

-- Get information about the latest available game version
local function get_latest_game_version_info(): RemoteGameInfo
    return list_remote_game_versions()[1]
end

-- Read currently installed game version, or nil if game is not installed
local function get_current_game_version(): string | nil
    if not fs.exists(game_version_path) then
        return nil
    end

    local version = fs.read_file(game_version_path):await()

    return str.from_bytes(version)
end

-- Write version string to the game version file
local function set_current_game_version(version: string)
    if not fs.exists(game_dir_path) then
        fs.create_dir(game_dir_path):await()
    end

    fs.write_file(game_version_path, version):await()
end

----------------------------- Settings -----------------------------

local __settings = nil

local function import_settings()
    if not __settings then
        local iter = import("iterable")

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

                                values = iter(list_remote_game_versions())
                                    .fold({}, function(values, info)
                                        values[info.version] = info.version

                                        return values
                                    end),

                                default = get_latest_game_version_info().version
                            }
                        }
                    }
                }
            }
        })
    end

    return __settings
end

----------------------------- Game version info -----------------------------

-- Return true if the game is installed and its version matches selected one
local function is_latest_game_version_installed(): boolean
    local version = get_current_game_version()

    if not version then
        return false
    end

    local settings = import_settings()

    return version == settings.get_property("game.version")
end

-- Return information about the selected game version, or nil if it's not found
local function get_selected_game_version_info(): RemoteGameInfo | nil
    local settings = import_settings()

    local selected_game_version = settings.get_property("game.version")

    if not selected_game_version then
        return get_latest_game_version_info()
    end

    local iter = import("iterable")

    return iter(list_remote_game_versions())
        .find(function(game) return game.version == selected_game_version end)
end

----------------------------- File checksum -----------------------------

-- Calculate hash of a file with the given path
local function calc_file_hash(path: string): string
    local file_hash = hash.digitize_file("seahash", path):await()

    return str.encode("hex", file_hash)
end

----------------------------- Module -----------------------------

return function()
    local __is_nixos = path.exists("/etc/NIXOS")
    local __has_steam_run = nil

    if __is_nixos then
        __has_steam_run = system.find("steam-run") ~= nil
    end

    return {
        game = {
            get_launch_info = function(variant: GameVariant)
                if not get_current_jre_version()
                    or not is_latest_game_version_installed()
                then
                    return nil
                end

                -- Normal systems
                if not __is_nixos then
                    return {
                        binary = jre_binary_path,
                        args = { "-jar", game_jar_path }
                    }

                -- Mental disorder
                --
                -- NixOS can't load some libraries which are extracted from the
                -- Mindustry's jar file, so we have to wrap it with steam-run
                -- which somehow fixes the problem
                else
                    if not __has_steam_run then
                        portal.toast({
                            message = i18n("nixos_steam_run_required")
                        })

                        return nil
                    end

                    return {
                        binary = "steam-run",
                        args = { jre_binary_path, "-jar", game_jar_path }
                    }
                end
            end,

            get_actions_pipeline = function(variant: GameVariant)
                -- Store update info in these variables
                local jre_update_info: RemoteJreInfo | nil = nil
                local game_update_info: RemoteGameInfo | nil = nil

                -- Load remote JRE info and compare it with the currently
                -- installed one
                local jre_info = get_remote_jre_info()

                if get_current_jre_version() ~= jre_info.version then
                    jre_update_info = jre_info
                end

                -- Load selected game info and compare it with the currently
                -- installed one
                local game_info = get_selected_game_version_info()
                    or get_latest_game_version_info()

                if get_current_game_version() ~= game_info.version then
                    game_update_info = game_info
                end

                -- Skip actions pipeline completely if neither needs an update
                if not jre_update_info and not game_update_info then
                    return nil
                end

                -- Otherwise prepare a pipeline
                local pipeline = {}

                -- Update JRE
                if jre_update_info then
                    local jre_temp_archive_path: string = path.join(path.temp_dir(), `mindustry-{jre_update_info.name}.tar.gz`)
                    local jre_temp_extract_path: string = path.join(path.temp_dir(), `mindustry-{jre_update_info.name}`)

                    table.insert(pipeline, {
                        title = i18n("delete_old_jre"),

                        before = function()
                            return fs.exists(jre_dir_path)
                        end,

                        perform = function()
                            fs.remove_dir(jre_dir_path):await()
                        end
                    })

                    table.insert(pipeline, {
                        title = i18n("download_jre"),

                        perform = function(updater)
                            local downloader_handle = downloader.create()

                            local task_handle = downloader.download(downloader_handle, {
                                url = jre_update_info.url,
                                output_file = jre_temp_archive_path,
                                continue_download = false,

                                on_update = function(current: number, total: number)
                                    updater({
                                        current = current,
                                        total = total,

                                        format = function()
                                            return i18n("downloading_progress_mb", {
                                                current = string.format("%.2f", current / 1024 / 1024),
                                                total = string.format("%.2f", total / 1024 / 1024)
                                            })
                                        end
                                    })
                                end
                            })

                            downloader.wait(task_handle)
                            downloader.close(downloader_handle)

                            local jre_archive_hash = calc_file_hash(jre_temp_archive_path)

                            if jre_archive_hash ~= jre_update_info.hash then
                                fs.remove(jre_temp_archive_path):await()

                                print(`{jre_update_info.name} hash: {jre_archive_hash}`)

                                error("downloaded JRE archive has invalid hash")
                            end
                        end
                    })

                    table.insert(pipeline, {
                        title = i18n("extract_jre"),

                        perform = function(updater)
                            if fs.exists(jre_temp_extract_path) then
                                fs.remove_dir(jre_temp_extract_path):await()
                            end

                            fs.create_dir(jre_temp_extract_path):await()

                            local archive_handle = archive.open(jre_temp_archive_path)

                            archive.extract(
                                archive_handle,
                                jre_temp_extract_path,
                                function(current: number, total: number)
                                    updater({
                                        current = current,
                                        total = total,

                                        format = function()
                                            return i18n("extracting_progress_mb", {
                                                current = string.format("%.2f", current / 1024 / 1024),
                                                total = string.format("%.2f", total / 1024 / 1024)
                                            })
                                        end
                                    })
                                end
                            )

                            archive.close(archive_handle)

                            fs.move(path.join(jre_temp_extract_path, jre_update_info.name), jre_dir_path):await()

                            fs.remove(jre_temp_archive_path):await()
                            fs.remove(jre_temp_extract_path):await()

                            set_current_jre_version(jre_update_info.version)
                        end
                    })
                end

                -- Update game
                if game_update_info then
                    table.insert(pipeline, {
                        title = i18n("delete_old_game"),

                        before = function()
                            return fs.exists(game_dir_path)
                        end,

                        perform = function()
                            fs.remove_dir(game_dir_path):await()
                        end
                    })

                    table.insert(pipeline, {
                        title = i18n("download_game"),

                        perform = function(updater)
                            if not fs.exists(game_dir_path) then
                                fs.create_dir(game_dir_path):await()
                            end

                            local downloader_handle = downloader.create()

                            local task_handle = downloader.download(downloader_handle, {
                                url = game_update_info.url,
                                output_file = game_jar_path,
                                continue_download = false,

                                on_update = function(current: number, total: number)
                                    updater({
                                        current = current,
                                        total = total,

                                        format = function()
                                            return i18n("downloading_progress_mb", {
                                                current = string.format("%.2f", current / 1024 / 1024),
                                                total = string.format("%.2f", total / 1024 / 1024)
                                            })
                                        end
                                    })
                                end
                            })

                            downloader.wait(task_handle)
                            downloader.close(downloader_handle)

                            local game_jar_hash = calc_file_hash(game_jar_path)

                            if game_jar_hash ~= game_update_info.hash then
                                fs.remove(game_jar_path):await()

                                print(`Mindustry {game_update_info.version} hash: {game_jar_hash}`)

                                error("downloaded game has invalid hash")
                            end

                            set_current_game_version(game_update_info.version)
                        end
                    })
                end

                -- Change title depending on the pipeline content
                local pipeline_title = i18n("install")

                if jre_update_info and not game_update_info then
                    pipeline_title = i18n("install_jre")
                elseif game_update_info and not jre_update_info then
                    pipeline_title = i18n("install_game")
                end

                return {
                    title = pipeline_title,
                    pipeline = pipeline
                }
            end,
        },

        components = {
            get_layout = function()
                -- Prepare JRE component info
                local jre_component = {
                    name = "jre",
                    title = "Java Runtime Environment",
                    locked = true
                }

                local current_jre_version = get_current_jre_version()

                if current_jre_version then
                    local jre_version_record = {
                        title = i18n("version"),
                        value = current_jre_version,
                        status = "success"
                    }

                    if get_remote_jre_info().version ~= current_jre_version then
                        jre_version_record.status = "warning"
                        jre_version_record.description = i18n("version_outdated")
                    end

                    jre_component.values = {
                        jre_version_record
                    }
                end

                -- Prepare game component info
                local game_component = {
                    name = "game",
                    title = i18n("game"),
                    locked = true
                }

                local current_game_version = get_current_game_version()

                if current_game_version then
                    local game_version_record = {
                        title = i18n("version"),
                        value = current_game_version,
                        status = "success"
                    }

                    if get_latest_game_version_info().version ~= current_game_version then
                        game_version_record.status = "warning"
                        game_version_record.description = i18n("version_outdated")
                    end

                    game_component.values = {
                        game_version_record
                    }
                end

                return {
                    {
                        entries = {
                            jre_component,
                            game_component
                        }
                    }
                }
            end,

            get_enabled = function() return true end,
            set_enabled = function() end,

            uninstall = function(variant: GameVariant, component: string)
                if component == "game" then
                    fs.remove_dir(game_dir_path):await()
                elseif component == "jre" then
                    fs.remove_dir(jre_dir_path):await()
                end
            end
        },

        settings = {
            get_layout = function(variant: GameVariant)
                local settings = import_settings()

                return settings.get_layout(variant)
            end,

            get_property = function(name: string): any
                local settings = import_settings()

                return settings.get_property(name)
            end,

            set_property = function(name: string, value: any)
                local settings = import_settings()

                settings.set_property(name, value)
            end
        }
    }
end
