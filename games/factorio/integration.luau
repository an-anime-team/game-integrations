-- Factorio integration v1.0.1
-- Copyright (C) 2026  mrkyss <mkryss@dawn.wine>
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

if not import then
    -- polyfill: old agl-runtime versions don't have `import` function
    function import(name: string)
        local resource = load(name)

        if resource.format ~= "package" then
            return resource.value
        end

        local outputs = {}

        for name, value in pairs(resource.value) do
            outputs[name] = value.value
        end

        return outputs
    end
end

type GameEdition = "standard" | "space_age"
type GameBuild = "alpha" | "expansion"

type GameVariant = {
    platform: string,
    edition: GameEdition
}

----------------------------- Paths and constants -----------------------------

local data_dir_path: string = path.persist_dir("factorio")

local game_dir_paths: { [GameEdition]: string } = {
    standard  = path.join(data_dir_path, "standard"),
    space_age = path.join(data_dir_path, "space-age")
}

local game_version_file_paths: { [GameEdition]: string } = {
    standard  = path.join(game_dir_paths["standard" :: GameEdition],  ".version"),
    space_age = path.join(game_dir_paths["space_age" :: GameEdition], ".version")
}

local game_binary_paths: { [GameEdition]: string } = {
    standard  = path.join(game_dir_paths["standard" :: GameEdition],  "factorio", "bin", "x64", "factorio"),
    space_age = path.join(game_dir_paths["space_age" :: GameEdition], "factorio", "bin", "x64", "factorio")
}

local credentials_dir_path: string = path.module_dir()
local credentials_token_path: string = path.join(credentials_dir_path, "token")

local game_editions_to_builds: { [GameEdition]: GameBuild } = {
    standard  = "alpha",
    space_age = "expansion"
}

----------------------------- Imports -----------------------------

local __i18n = nil

local function i18n(...)
    if not __i18n then
        local locales = import("locales")

        locales = fs.read_file(locales):await()
        locales = str.decode("toml", str.from_bytes(locales))

        __i18n = import("i18n").i18n(locales)
    end

    return (__i18n)(...)
end

----------------------------- Credentials -----------------------------

-- Read account token from the private game integration storage
local function get_account_token(): string?
    local promise = fs.read_file(credentials_token_path)

    local result, token = pcall(await, promise)

    if not result then
        return nil
    end

    return str.from_bytes(token)
end

-- Write account token to the private game integration storage
local function set_account_token(token: string)
    if not fs.exists(credentials_dir_path) then
        fs.create_dir(credentials_dir_path):await()
    end

    if token and str.trim(token) ~= "" then
        fs.write_file(credentials_token_path, token):await()
    else
        fs.remove(credentials_token_path):await()
    end
end

-- Validate account username and token. Return true if both are fine. Otherwise
-- return false and use portal API to notify user about invalid credentials.
local function validate_credentials(
    username: string?,
    token: string?
): (boolean, string?, string?)
    username = if username then str.trim(username) else nil
    token = if token then str.trim(token) else nil

    if username == "" then
        username = nil
    end

    if token == "" then
        token = nil
    end

    if not username and not token then
        portal.toast({ message = i18n("credentials_required_message") })

        return false, username, token
    elseif not username and token then
        portal.toast({ message = i18n("credentials_username_required_message") })

        return false, username, token
    elseif username and not token then
        portal.toast({ message = i18n("credentials_token_required_message") })

        return false, username, token
    end

    return true, username, token
end

----------------------------- Settings -----------------------------

local __settings = nil

local __games_api_version: string? = nil

local function import_settings()
    if not __settings then
        __settings = import("settings")({
            game = "factorio",
            layout = {
                credentials = {
                    title = i18n("game_account_credentials_title"),
                    description = i18n("game_account_credentials_description"),

                    entries = {
                        username = {
                            title = i18n("game_account_credentials_username_title"),

                            entry = {
                                format = "text",
                                default = ""
                            }
                        },

                        token = {
                            title = i18n("game_account_credentials_token_title"),
                            description = i18n("game_account_credentials_token_description"),

                            entry = {
                                -- "secret_text" has been added in v0.2.0
                                format = if __games_api_version == "0.1.0"
                                    then "text"
                                    else "secret_text",

                                default = ""
                            },

                            options = {
                                get = function()
                                    return get_account_token()
                                end,

                                set = function(value)
                                    set_account_token(value)
                                end
                            }
                        }
                    }
                }
            }
        })
    end

    return __settings
end

----------------------------- Game versions -----------------------------

local __latest_game_versions: { [GameEdition]: string }? = nil

-- Get list of latest available game versions
local function get_latest_game_versions(): { [GameEdition]: string }
    if __latest_game_versions ~= nil then
        return clone(__latest_game_versions)
    end

    local response = http.fetch("https://factorio.com/api/latest-releases"):await()

    if not response.is_ok then
        error(`failed to fetch latest releases: {response.status}`)
    end

    local releases = str.decode("json", str.from_bytes(response.body))

    __latest_game_versions = {
        standard  = releases.stable.alpha :: string,
        space_age = releases.stable.expansion :: string
    }

    return clone(__latest_game_versions)
end

-- Get installed game version of given edition
local function get_game_version(edition: GameEdition): string?
    local version_path = game_version_file_paths[edition or ("standard" :: GameEdition)]
        or error(`invalid game edition: {edition}`)

    if not fs.exists(version_path) then
        return nil
    end

    local version = fs.read_file(version_path):await()

    return str.from_bytes(version)
end

-- Set installed game version of given edition
local function set_game_version(edition: GameEdition, version: string)
    local version_path = game_version_file_paths[edition or ("standard" :: GameEdition)]
        or error(`invalid game edition: {edition}`)

    fs.write_file(version_path, version):await()
end

----------------------------- Module -----------------------------

type RuntimeInfo = {
    -- agl-games version
    version: string,

    -- host platform
    platform: string?
}

return function(runtime: RuntimeInfo)
    __games_api_version = runtime.version

    local __is_nixos = path.exists("/etc/NIXOS")
    local __has_steam_run = nil

    if __is_nixos then
        __has_steam_run = system.find("steam-run") ~= nil
    end

    return {
        game = {
            get_editions = function(platform): {{ name: GameEdition, title: any }}
                return {
                    {
                        name = "standard" :: GameEdition,
                        title = i18n("edition_standard_title")
                    },
                    {
                        name = "space_age" :: GameEdition,
                        title = i18n("edition_space_age_title")
                    }
                }
            end,

            get_launch_info = function(variant: GameVariant): { binary: string, args: { string }? }?
                variant.edition = variant.edition or "standard"

                -- We can't launch the game without account username and token
                local settings = import_settings()

                local status = validate_credentials(
                    settings.get_property("credentials.username"),
                    settings.get_property("credentials.token")
                )

                if not status then
                    return nil
                end

                -- We can't launch the game if it's not installed
                local binary_path = game_binary_paths[variant.edition]
                    or error(`invalid game edition: {variant.edition}`)

                if not fs.exists(binary_path) then
                    return nil
                end

                -- We don't have to verify installed game version, user can
                -- run it without updating

                -- Normal systems
                if not __is_nixos then
                    return {
                        binary = binary_path
                    }

                -- Mental disorder
                --
                -- NixOS can't run factorio directly, so we have to wrap it with
                -- steam-run which fixes the problem
                else
                    if not __has_steam_run then
                        portal.toast({
                            message = i18n("nixos_steam_run_required")
                        })

                        return nil
                    end

                    return {
                        binary = "steam-run",
                        args = { binary_path }
                    }
                end
            end,

            get_actions_pipeline = function(variant: GameVariant): any
                variant.edition = variant.edition or "standard"

                local latest_game_versions = get_latest_game_versions()

                local latest_game_version = latest_game_versions[variant.edition]
                    or error(`invalid game edition: {variant.edition}`)

                local current_game_version = get_game_version(variant.edition)

                -- If the game is installed and its version matches latest
                -- available version then don't do anything
                if current_game_version ~= nil and current_game_version == latest_game_version then
                    return nil
                end

                -- Check account credentials which are required to download game
                -- files
                local settings = import_settings()

                local status, account_username, account_token = validate_credentials(
                    settings.get_property("credentials.username"),
                    settings.get_property("credentials.token")
                )

                if not status then
                    return nil
                end

                -- Prompt user to install (update) the game
                local game_build: GameBuild = game_editions_to_builds[variant.edition]
                    or error(`invalid game edition: {variant.edition}`)

                local temp_archive_path: string = path.join(path.temp_dir(), `factorio-{variant.edition}-{latest_game_version}.tar.xz`)

                local game_dir_path: string = game_dir_paths[variant.edition]
                    or error(`invalid game edition: {variant.edition}`)

                return {
                    -- Change title depending on the game installation status
                    title = if not current_game_version
                        then i18n("install_game_title")
                        else i18n("update_game_title"),

                    pipeline = {
                        {
                            title = i18n("delete_old_game_files_title"),

                            before = function()
                                return fs.exists(game_dir_path)
                            end,

                            perform = function(updater)
                                fs.remove_dir(game_dir_path):await()
                            end
                        },
                        {
                            title = i18n("download_game_files_title"),

                            perform = function(updater)
                                -- Try to start game archive downloading.
                                --
                                -- We're using HTTP API here instead of the
                                -- Downloader API because we dont' want download
                                -- URL to leak in the launcher logs.
                                local response = http.open(`https://www.factorio.com/get-download/{latest_game_version}/{game_build}/linux64?username={account_username}&token={account_token}`):await()

                                if not response.is_ok then
                                    error(`failed to start downloading the game: {response.status}`)
                                end

                                local total = tonumber(response.headers["Content-Length"]) or 0
                                local current = 0

                                -- Open game archive file
                                local file_handle = fs.open(temp_archive_path, {
                                    write     = true,
                                    create    = true,
                                    overwrite = true
                                })

                                -- Read game archive chunks and write them to
                                -- the output file
                                local chunk = http.read(response.handle):await()

                                while chunk do
                                    fs.write(file_handle, chunk)

                                    current += #chunk

                                    if current > total then
                                        total = current
                                    end

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

                                    chunk = http.read(response.handle):await()
                                end

                                fs.flush(file_handle)
                                fs.close(file_handle)

                                http.close(response.handle)
                            end
                        } :: any,
                        {
                            title = i18n("extract_game_files_title"),

                            perform = function(updater)
                                if fs.exists(game_dir_path) then
                                    fs.remove_dir(game_dir_path):await()
                                end

                                fs.create_dir(game_dir_path):await()

                                local archive_handle = archive.open(temp_archive_path)

                                archive.extract(
                                    archive_handle,
                                    game_dir_path,
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

                                fs.remove(temp_archive_path):await()

                                set_game_version(variant.edition, latest_game_version)
                            end
                        } :: any
                    }
                }
            end
        },

        components = {
            get_layout = function()
                return {
                    {
                        entries = {
                            {
                                name = "game_standard",
                                title = i18n("component_edition_standard_title"),
                                locked = true,
                                values = {
                                    {
                                        title = i18n("version"),
                                        value = get_game_version("standard") or i18n("game_not_installed_title")
                                    }
                                }
                            },
                            {
                                name = "game_space_age",
                                title = i18n("component_edition_space_age_title"),
                                locked = true,
                                values = {
                                    {
                                        title = i18n("version"),
                                        value = get_game_version("space_age") or i18n("game_not_installed_title")
                                    }
                                }
                            }
                        }
                    }
                }
            end,

            get_enabled = function() return true end,
            set_enabled = function() end,

            uninstall = function(variant: GameVariant, component: string)
                if component == "game_standard" then
                    local game_dir_path = game_dir_paths["standard" :: GameEdition]
                        or error("invalid game edition: standard")

                    fs.remove_dir(game_dir_path):await()

                elseif component == "game_space_age" then
                    local game_dir_path = game_dir_paths["space_age" :: GameEdition]
                        or error("invalid game edition: space_age")

                    fs.remove_dir(game_dir_path):await()
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
