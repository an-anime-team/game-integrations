-- Factorio integration v0.0.0
-- Copyright (C) 2026  mrkyss <mkryss@dawn.wine>
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

------------------------------------------ Paths ----------------------------------------------

local data_dir_path: string = path.persist_dir("factorio")

local function get_game_dir(edition: string?): string
    edition = edition or "standard"
    return path.join(data_dir_path, edition)
end

local function get_version_path(edition: string?): string
    edition = edition or "standard"
    return path.join(data_dir_path, "." .. edition .. ".version")
end

local function get_binary_path(edition: string?): string
    edition = edition or "standard"
    return path.join(get_game_dir(edition), "factorio", "bin", "x64", "factorio")
end

local private_dir_path: string = path.module_dir()
local credentials_path: string = path.join(private_dir_path, "credentials.json")

--------------------------------------- Credentials -------------------------------------------

local function get_private_credentials()
    if not fs.exists(credentials_path) then
        return { username = "", token = "" }
    end

    local data = fs.read_file(credentials_path):await()
    return str.decode("json", str.from_bytes(data))
end

local function set_private_credentials(creds)
    if not fs.exists(private_dir_path) then
        fs.create_dir(private_dir_path):await()
    end
    fs.write_file(credentials_path, str.to_bytes(str.encode("json", creds))):await()
end

----------------------------------------- Imports ---------------------------------------------

local __i18n = nil
local __settings = nil

local function i18n(...)
    if not __i18n then
        local locales = import("locales")

        locales = fs.read_file(locales):await()
        locales = str.decode("toml", str.from_bytes(locales))

        __i18n = import("i18n").i18n(locales)
    end

    return (__i18n)(...)
end

local function import_settings()
    if not __settings then
        __settings = import("settings")({
            game = "factorio",
            layout = {
                credentials = {
                    title = i18n("credentials_group"),
                    description = i18n("credentials_description"),
                    entries = {
                        username = {
                            title = i18n("username"),
                            entry = {
                                format = "text",
                                default = ""
                            },
                            options = {
                                get = function()
                                    return get_private_credentials().username
                                end,
                                set = function(value)
                                    local creds = get_private_credentials()
                                    creds.username = value
                                    set_private_credentials(creds)
                                    return nil
                                end
                            }
                        },
                        token = {
                            title = i18n("token"),
                            entry = {
                                format = "secret_text",
                                default = ""
                            },
                            options = {
                                get = function()
                                    return get_private_credentials().token
                                end,
                                set = function(value)
                                    local creds = get_private_credentials()
                                    creds.token = value
                                    set_private_credentials(creds)
                                    return nil
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

----------------------------------------- Versions --------------------------------------------

local function get_latest_releases()
    local resp = http.fetch("https://factorio.com/api/latest-releases", { method = "get" }):await()

    if not resp.is_ok then
        error(`failed to fetch latest releases: {resp.status}`)
    end

    return str.decode("json", str.from_bytes(resp.body))
end

---------------------------------------- Game state -------------------------------------------

local function get_game_version(edition: string): string?
    local version_path = get_version_path(edition)
    if not fs.exists(version_path) then
        return nil
    end

    return str.from_bytes(fs.read_file(version_path):await())
end

local function set_game_version(edition: string, version: string)
    local version_path = get_version_path(edition)
    fs.write_file(version_path, str.to_bytes(version)):await()
end

local function is_game_installed(edition: string): boolean
    local version = get_game_version(edition)

    if not version then
        return false
    end

    return fs.exists(get_binary_path(edition))
end

------------------------------------------ Module ---------------------------------------------

return {
    version = 1,

    game = {
        get_editions = function(platform)
            return {
                {
                    name = "standard",
                    title = i18n("standard_edition")
                },
                {
                    name = "space-age",
                    title = i18n("space_age_edition")
                }
            }
        end,

        get_launch_info = function(variant: Variant)
            if not is_game_installed(variant.edition) then
                return nil
            end

            return {
                binary = get_binary_path(variant.edition),
                args = {}
            }
        end,

        get_actions_pipeline = function(variant: Variant)
            local settings = import_settings()

            local username = settings.get_property("credentials.username")
            local token = settings.get_property("credentials.token")

            if not username or username == "" or not token or token == "" then
                portal.toast({ message = i18n("missing_credentials") })
                return nil
            end

            local result, releases = pcall(get_latest_releases)
            if not result then
                return nil
            end

            local build = if variant.edition == "space-age" then "expansion" else "alpha"
            local version = releases.stable[build]

            if is_game_installed(variant.edition) and get_game_version(variant.edition) == version then
                return nil
            end

            local archive_path = path.join(path.temp_dir(), `factorio-{variant.edition}-{version}.tar.xz`)

            return {
                title = i18n("install_game_title"),
                pipeline = {
                    {
                        title = i18n("download_game_files_title"),
                        perform = function(updater)
                            local download_url = `https://www.factorio.com/get-download/{version}/{build}/linux64?username={username}&token={token}`

                            local response = http.open(download_url):await()
                            if not response.is_ok then
                                error(`failed to start download: {response.status}`)
                            end

                            local total = tonumber(response.headers["content-length"]) or 0
                            local current = 0

                            local file_handle = fs.open(archive_path, {
                                create = true,
                                overwrite = true,
                                write = true
                            })

                            local chunk = http.read(response.handle):await()
                            while chunk do
                                fs.write(file_handle, chunk:as_string())
                                current = current + #chunk

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

                            fs.close(file_handle)
                            http.close(response.handle)
                        end
                    },
                    {
                        title = i18n("extract_game_files_title"),
                        perform = function(updater)
                            local game_dir = get_game_dir(variant.edition)
                            if fs.exists(game_dir) then
                                fs.remove_dir(game_dir):await()
                            end

                            fs.create_dir(game_dir):await()

                            local handle = archive.open(archive_path)

                            archive.extract(handle, game_dir, function(current, total)
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
                            end)

                            archive.close(handle)
                            fs.remove(archive_path):await()

                            set_game_version(variant.edition, version)
                        end
                    }
                }
            }
        end
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
