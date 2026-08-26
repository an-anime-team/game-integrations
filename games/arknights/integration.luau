-- Arknights integration v0.1.1
-- Copyright (C) 2026  Nikita Podvirnyi <krypt0nn@dawn.wine>
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

local DATA_DIR: string = path.persist_dir("arknights")

local GAME_DIR: { [GameEdition]: string } = {
    global = path.join(DATA_DIR, "global_game_files"),
    japan = path.join(DATA_DIR, "japan_game_files"),
    korea = path.join(DATA_DIR, "korea_game_files")
}

local GAME_BINARY: { [GameEdition]: string } = {
    global = path.join(GAME_DIR["global"], "Arknights.exe"),
    japan = path.join(GAME_DIR["japan"], "Arknights.exe"),
    korea = path.join(GAME_DIR["korea"], "Arknights.exe")
}

local GAME_VERSION_PATH: { [GameEdition]: string } = {
    global = path.join(GAME_DIR["global"], ".version"),
    japan = path.join(GAME_DIR["japan"], ".version"),
    korea = path.join(GAME_DIR["korea"], ".version")
}

local GAME_API_INFO: { [GameEdition]: {
    api_url: string,
    cdn_url: string,
    tag: string,
    salt: string
} } = {
    global = {
        api_url = "https://api-launcher-en.yo-star.com",
        cdn_url = "https://launcher-pkg-ark-en.yo-star.com",
        tag = "Arknights_EN",
        salt = "DE7108E9B2842FD460F4777702727869"
    },
    japan = {
        api_url = "https://api-launcher-jp.yo-star.com",
        cdn_url = "https://launcher-pkg-ark-jp.yo-star.com",
        tag = "Arknights_JP",
        salt = "DE7108E9B2842FD460F4777702727869"
    },
    korea = {
        api_url = "https://api-launcher-kr.yo-star.com",
        cdn_url = "https://launcher-pkg-ark-kr.yo-star.com",
        tag = "Arknights_KR",
        salt = "DE7108E9B2842FD460F4777702727869"
    }
}

type GameEdition = "global" | "japan" | "korea"

type GameVariant = {
    platform: string,
    edition: GameEdition
}

----------------------------- translations -----------------------------

local __i18n = nil

local function i18n(...)
    if not __i18n then
        local locales = import("locales-src")

        locales = fs.read_file(locales):await()
        locales = str.decode("toml", str.from_bytes(locales))

        __i18n = import("i18n").i18n(locales)
    end

    return (__i18n)(...)
end

----------------------------- game api -----------------------------

-- avoid parsing everything after a `#` symbol as an URL fragment
local function url_encode_path(file_path: string): string
    return (file_path:gsub("#", "%%23"))
end

local __api_auth_header: { [GameEdition]: string } = {}

local function api_get_auth_header(edition: GameEdition): string
    if __api_auth_header[edition] then
        return __api_auth_header[edition]
    end

    local head = `\{"game_tag":"{GAME_API_INFO[edition].tag}","time":{system.utc_time()},"version":"1.6.0"\}`
    local sign = str.encode("hex", hash.digitize("md5", `{head}{GAME_API_INFO[edition].salt}`))

    __api_auth_header[edition] = `\{"head":{head},"sign":"{sign}"\}`

    return __api_auth_header[edition]
end

local __api_game_info: { [GameEdition]: { version: string, file_path: string } } = {}

local function api_query_game_info(edition: GameEdition): { version: string, file_path: string }?
    if __api_game_info[edition] then
        return __api_game_info[edition]
    end

    local response = http.fetch(`{GAME_API_INFO[edition].api_url}/api/launcher/game/config`, {
        headers = {
            authorization = api_get_auth_header(edition)
        }
    }):await()

    if not response.is_ok then
        return nil
    end

    response = str.decode("json", response.body:as_string())

    if response.code ~= 200 then
        return nil
    end

    __api_game_info[edition] = {
        version = response.data.game_latest_version,
        file_path = response.data.game_latest_file_path
    }

    return __api_game_info[edition]
end

local __api_game_files: { [string]: {
    source: string,
    files: { path: string, size: string, hash: string }
} } = {}

local function api_query_game_files(
    edition: GameEdition,
    version: string?
): {
    source: string,
    files: { path: string, size: string, hash: string }
}?
    local cache_key = `{edition}-{version}`

    if version and __api_game_files[cache_key] then
        return __api_game_files[cache_key]
    end

    local game_info = api_query_game_info(edition)

    if not game_info then
        return nil
    end

    cache_key = `{edition}-{version or game_info.version}`

    -- Query CDN URL for the game files of given game version.
    local response = http.fetch(`{GAME_API_INFO[edition].api_url}/api/launcher/game/config/json?version={version or game_info.version}&file_path={game_info.file_path}`, {
        headers = {
            authorization = api_get_auth_header(edition)
        }
    }):await()

    if not response.is_ok then
        return nil
    end

    response = str.decode("json", response.body:as_string())

    if response.code ~= 200 then
        return nil
    end

    -- Query list of files using obtained URL.
    response = http.fetch(response.data.url):await()

    if not response.is_ok then
        return nil
    end

    response = str.decode("json", response.body:as_string())

    __api_game_files[cache_key] = {
        source = response.source,
        files = response.file
    }

    return __api_game_files[cache_key]
end

----------------------------- versions -----------------------------

local function game_version_read(edition: GameEdition): string?
    local version_path = GAME_VERSION_PATH[edition]

    if not fs.exists(version_path) then
        return nil
    end

    local version = fs.read_file(version_path):await()

    return str.from_bytes(version)
end

local function game_version_write(edition: GameEdition, version: string)
    local version_path = GAME_VERSION_PATH[edition]

    fs.write_file(version_path, str.to_bytes(version)):await()
end

----------------------------- settings -----------------------------

local __settings = nil

local function get_settings()
    if not __settings then
        __settings = import("settings")({
            game = "arknights",
            layout = {
                {
                    name = "downloader",
                    title = i18n("downloader_settings_title"),
                    entries = {
                        {
                            name = "target_memory_usage",
                            title = i18n("downloader_settings_target_memory_usage_title"),
                            description = i18n("downloader_settings_target_memory_usage_description"),
                            reactivity = "none",
                            entry = {
                                format = "number",
                                min = 64,
                                max = 2048,
                                step = 64,
                                default = 256
                            }
                        },
                        {
                            name = "max_parallel_streams",
                            title = i18n("downloader_settings_max_parallel_streams_title"),
                            description = i18n("downloader_settings_max_parallel_streams_description"),
                            reactivity = "none",
                            entry = {
                                format = "number",
                                min = 0,
                                max = 256,
                                step = 16,
                                default = 64
                            }
                        }
                    }
                }
            }
        })
    end

    return __settings
end

----------------------------- pipelines -----------------------------

local function get_download_game_pipeline(
    edition: GameEdition,
    version: string,
    target_memory_usage: number?,
    max_parallel_streams: number?
)
    local target_memory_usage = target_memory_usage or 256 * 1024 * 1024
    local max_parallel_streams = max_parallel_streams or 64

    local game_files: { [string]: { url: string, size: number } } = {}

    return {
        title = i18n("install_game_title"),
        pipeline = {
            {
                title = i18n("fetch_download_info_title"),

                perform = function()
                    local game_files_info = api_query_game_files(edition, version)

                    if game_files_info then
                        for _, file_info in pairs(game_files_info.files) do
                            local file_url_path = url_encode_path(`{game_files_info.source}{file_info.path}`)

                            game_files[file_info.path] = {
                                url = `{GAME_API_INFO[edition].cdn_url}{file_url_path}`,
                                size = tonumber(file_info.size) or 0
                            }
                        end
                    end
                end
            } :: any,
            {
                title = i18n("verify_available_files_title"),

                before = function()
                    local has_files = false

                    for _, _ in pairs(game_files) do
                        has_files = true

                        break
                    end

                    return has_files
                end,

                perform = function(updater: any)
                    local curr_progress = 0
                    local total_progress = 0

                    for _, file_info in pairs(game_files) do
                        total_progress += file_info.size
                    end

                    for file_path, file_info in pairs(game_files) do
                        local status, metadata = pcall(fs.metadata, path.join(GAME_DIR[edition], file_path))

                        if status and metadata and metadata.length == file_info.size then
                            game_files[file_path] = nil
                        end

                        updater({
                            current = curr_progress,
                            total = total_progress,
                            format = function()
                                return i18n("verifying_progress_gb", {
                                    current = string.format("%.2f", curr_progress / 1024 / 1024 / 1024),
                                    total = string.format("%.2f", total_progress / 1024 / 1024 / 1024)
                                })
                            end
                        })
                    end
                end
            },
            {
                title = i18n("download_new_files_title"),

                before = function()
                    local has_files = false

                    for _, _ in pairs(game_files) do
                        has_files = true

                        break
                    end

                    return has_files
                end,

                perform = function(updater: any)
                    local curr_progress = 0
                    local total_progress = 0

                    for _, file_info in pairs(game_files) do
                        total_progress += file_info.size
                    end

                    local downloader_handle = downloader.create()

                    local queue: { [string]: { size: number, task_handle: any } } = {}

                    while true do
                        local queue_size = 0
                        local queue_count = 0

                        for file_path, download_info in pairs(queue) do
                            queue_size += download_info.size
                            queue_count += 1
                        end

                        -- If queue is empty, or both are true:
                        -- 1. queued files are under target memory usage value,
                        -- 2. less than max parallel files are queued
                        while queue_count == 0 or (
                            queue_size < target_memory_usage
                                and (max_parallel_streams > 0 and queue_count < max_parallel_streams)
                        )
                        do
                            local queued_file = false

                            for file_path, file_info in pairs(game_files) do
                                queue[file_path] = {
                                    size = file_info.size,
                                    task_handle = downloader.download(downloader_handle, {
                                        url = file_info.url,
                                        output_file = path.join(GAME_DIR[edition], file_path),
                                        continue_download = false
                                    })
                                }

                                queue_size += file_info.size
                                queue_count += 1

                                game_files[file_path] = nil

                                queued_file = true

                                break
                            end

                            -- no files left to queue
                            if not queued_file then
                                break
                            end
                        end

                        if queue_count == 0 then
                            break
                        end

                        while true do
                            local delta_current = 0
                            local has_any = false

                            for file_path, download_info in pairs(queue) do
                                local download_progress = downloader.progress(download_info.task_handle)

                                if download_progress.finished then
                                    downloader.wait(download_info.task_handle)

                                    curr_progress += download_info.size

                                    queue[file_path] = nil
                                else
                                    delta_current += math.min(download_progress.current, download_info.size)

                                    has_any = true
                                end
                            end

                            if not has_any then
                                break
                            end

                            updater({
                                current = curr_progress + delta_current,
                                total = total_progress,
                                format = function()
                                    return i18n("downloading_progress_gb", {
                                        current = string.format("%.2f", (curr_progress + delta_current) / 1024 / 1024 / 1024),
                                        total = string.format("%.2f", total_progress / 1024 / 1024 / 1024)
                                    })
                                end
                            })
                        end
                    end

                    downloader.close(downloader_handle)

                    game_version_write(edition, version)
                end
            }
        }
    }
end

----------------------------- integration -----------------------------

return function()
    local iter = import("iterable")

    local settings = get_settings()

    local lua_proton = import("lua-proton").proton({
        prefix = {
            name = "arknights"
        },

        settings = {
            get_property = settings.get_property,
            set_property = settings.set_property
        }
    })

    return {
        game = {
            get_editions = function(platform: string): {{ name: GameEdition, title: any }}
                return {
                    {
                        name = "global",
                        title = i18n("global_game_edition_title")
                    },
                    {
                        name = "japan",
                        title = i18n("japan_game_edition_title")
                    },
                    {
                        name = "korea",
                        title = i18n("korea_game_edition_title")
                    }
                }
            end,

            get_launch_info = function(variant: GameVariant)
                variant.edition = variant.edition or "global" :: GameEdition

                -- Check if we have game binary.
                if not fs.exists(GAME_BINARY[variant.edition]) then
                    return nil
                end

                -- Check if the game is installed.
                local game_version = game_version_read(variant.edition)

                if not game_version then
                    return nil
                end

                -- Check if lua-proton is ready to launch the game.
                if not lua_proton.game.can_launch() then
                    return nil
                end

                -- Query latest game info.
                local game_info = api_query_game_info(variant.edition)

                if not game_info then
                    return nil
                end

                -- Check if installed game version is not latest.
                if game_version ~= game_info.version then
                    return nil
                end

                -- Try to obtain game launch info from the lua-proton library.
                -- It will return nil if selected proton is not available.
                local launch_info = lua_proton.game.wrap_launch_info({
                    binary = GAME_BINARY[variant.edition]
                })

                if not launch_info then
                    return nil
                end

                -- Wrap game launch command with steam-run for NixOS hosts.
                local nixos_wrapper = import("nixos-command-wrapper")

                return nixos_wrapper(launch_info)
            end,

            get_actions_pipeline = function(variant: GameVariant)
                -- Update proton version.
                local proton_pipeline = lua_proton.game.get_actions_pipeline(variant)

                if proton_pipeline then
                    return proton_pipeline
                end

                -- Update game files.
                variant.edition = variant.edition or "global" :: GameEdition

                local target_memory_usage = settings.get_property("downloader.target_memory_usage")

                local game_version = game_version_read(variant.edition)
                local game_info = api_query_game_info(variant.edition)

                if not game_info then
                    return nil
                end

                if not game_version then
                    return get_download_game_pipeline(
                        variant.edition,
                        game_info.version,
                        target_memory_usage * 1024 * 1024
                    )
                end

                if game_info and game_version ~= game_info.version then
                    return get_download_game_pipeline(
                        variant.edition,
                        game_info.version,
                        target_memory_usage * 1024 * 1024
                    )
                end

                return nil
            end
        },

        components = {
            get_layout = function(variant: GameVariant)
                return lua_proton.components.get_layout(variant)
            end,

            get_enabled = lua_proton.components.get_enabled,
            set_enabled = lua_proton.components.set_enabled,

            uninstall = lua_proton.components.uninstall
        },

        settings = {
            get_layout = function(variant: GameVariant)
                return iter({})
                    .chain(settings.get_layout(variant))
                    .chain(lua_proton.settings.get_layout(variant))
                    .collect()
            end,

            get_property = function(name: string): any
                return settings.get_property(name)
            end,

            set_property = function(name: string, value: any)
                settings.set_property(name, value)
            end
        }
    }
end
