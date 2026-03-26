-- NIKKE integration v0.1.0
-- Copyright (C) 2026 NelloKudo <marshnelloosu@gmail.com>
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

------------------------------------------------- constants -------------------------------------------------

local NIKKE_SITE_BASE    = "https://nikke-en.com"
local NIKKE_ASSETS_JS    = NIKKE_SITE_BASE .. "/assets/aix-18872c9c.js"

local DWPROTON_API_URL   = "https://dawn.wine/api/v1/repos/dawn-winery/dwproton/releases?limit=1&page=1"
local DWPROTON_ASSET_POS = 2

-- fallback used for get_proton_name() when settings have nothing stored yet
local PROTON_DEFAULT_NAME = "dwproton"

-- launch retry: seconds to wait before checking --ProductName=nikke_launcher
local LAUNCH_MAX_RETRIES  = 10
local LAUNCH_WAIT_SECONDS = 8

------------------------------------------------- paths -------------------------------------------------

local data_dir_path: string    = path.persist_dir("nikke")

local umu_dir_path: string     = path.join(data_dir_path, "umu")
local umu_binary_path: string  = path.join(umu_dir_path, "umu-run")
local proton_dir_path: string  = path.join(data_dir_path, "proton")
local prefix_dir_path: string  = path.join(data_dir_path, "prefix")

------------------------------------------------- component management -------------------------------------------------

local function is_umu_installed(): boolean
    return fs.exists(umu_binary_path)
end

-- scans proton_dir_path for runners that have a valid wine64 binary.
local function get_available_protons(): { [string]: string }
    local protons = {}

    if not fs.exists(proton_dir_path) then
        return protons
    end

    for _, entry in fs.read_dir(proton_dir_path):await() do
        if entry.type == "directory" then
            if fs.exists(path.join(entry.path, "files", "bin", "wine64")) then
                protons[entry.name] = entry.name
            end
        end
    end

    return protons
end

local function get_proton_name(settings): string
    return settings.get_property("runner.proton") or PROTON_DEFAULT_NAME
end

local function is_proton_installed(settings): boolean
    return fs.exists(path.join(proton_dir_path, get_proton_name(settings), "files", "bin", "wine64"))
end

------------------------------------------------- game detection -------------------------------------------------

local function get_prefix_path(settings): string
    local prefix_name = settings.get_property("runner.prefix") or "nikke"
    return path.join(prefix_dir_path, prefix_name)
end

local function get_gameid(settings): string
    return settings.get_property("runner.gameid") or "umu-nikke"
end

local function is_game_installed(settings): boolean
    local nikke_launcher = path.join(get_prefix_path(settings), "pfx", "drive_c", "NIKKE", "Launcher", "nikke_launcher.exe")
    return fs.exists(nikke_launcher)
end

------------------------------------------------- installer version discovery -------------------------------------------------

-- fetches the js bundle and extracts the miniloader download url
local function get_installer_info(): ({url: string, filename: string}?, string?)
    local resp = http.fetch(NIKKE_ASSETS_JS, { method = "get" }):await()

    if not resp.is_ok then
        return nil, "Failed to fetch assets JS: HTTP " .. tostring(resp.status)
    end

    local body = str.from_bytes(resp.body)

    local loader_path = string.match(body, '"(/nikkeminiloader[^"]+%.exe)"')
    if not loader_path then
        return nil, "Could not extract miniloader path from JS bundle"
    end

    local filename = string.match(loader_path, "/([^/]+)$") or loader_path
    local url = NIKKE_SITE_BASE .. "/" .. loader_path:gsub("^/+", "")

    return { url = url, filename = filename }, nil
end

------------------------------------------------- latest proton discovery -------------------------------------------------

local function get_latest_proton_release(): ({name: string, tag: string, url: string}?, string?)
    local resp = http.fetch(DWPROTON_API_URL, { method = "get" }):await()

    if not resp.is_ok then
        return nil, "Failed to fetch releases: HTTP " .. tostring(resp.status)
    end

    local body = str.from_bytes(resp.body)

    local tag_name = string.match(body, '"tag_name"%s*:%s*"([^"]+)"')

    local urls = {}
    for url in string.gmatch(body, '"browser_download_url"%s*:%s*"([^"]+)"') do
        table.insert(urls, url)
    end

    if not tag_name or not urls[DWPROTON_ASSET_POS] then
        return nil, "Could not parse release info from Forgejo API"
    end

    -- archive name is the last path segment of the url without extension
    local archive_name = string.match(urls[DWPROTON_ASSET_POS], "/([^/]+)%.tar%.xz$") or (tag_name .. "-x86_64")

    return { name = archive_name, tag = tag_name, url = urls[DWPROTON_ASSET_POS] }, nil
end

------------------------------------------------- progress / speed helpers -------------------------------------------------

local __i18n = nil
local __umu = nil

local function i18n(...)
    if not __i18n then
        local locales_path  = import("locales")
        local locales_bytes = fs.read_file(locales_path):await()
        local locales_table = str.decode("toml", str.from_bytes(locales_bytes))

        __i18n = import("i18n").i18n(locales_table)
    end
    return (__i18n)(...)
end

local function import_umu()
    if not __umu then
        __umu = import("umu_launcher")(umu_binary_path)
    end

    return __umu
end



------------------------------------------------- Launch wrapper -------------------------------------------------

-- writes a bash script that retries the launch when nikke_launcher never appears.
-- invoked via /bin/bash so no chmod needed (process is not available in get_launch_info).
local function create_launch_wrapper(prefix_path: string, proton_name: string): string
    local wrapper_path    = path.join(data_dir_path, "nikke-launch-wrapper.sh")
    local wineserver_path = path.join(proton_dir_path, proton_name, "files", "bin", "wineserver")
    local wineprefix      = path.join(prefix_path, "pfx")

    local script = string.format(
        "MAX_RETRIES=%d\n"
        .. "WAIT_SECONDS=%d\n"
        .. "WINEPREFIX_PATH=%q\n"
        .. "WINESERVER=%q\n"
        .. "\n"
        .. "for attempt in $(seq 1 \"$MAX_RETRIES\"); do\n"
        .. '    "$@" &\n'
        .. "    GAME_PID=$!\n"
        .. '    sleep "$WAIT_SECONDS"\n'
        .. "    if ps aux | grep -q '[--]ProductName=nikke_launcher'; then\n"
        .. '        wait "$GAME_PID"\n'
        .. "        exit $?\n"
        .. "    else\n"
        .. '        echo "[nikke-wrapper] attempt $attempt: nikke_launcher not detected, retrying..."\n'
        .. '        WINEPREFIX="$WINEPREFIX_PATH" "$WINESERVER" -k 2>/dev/null\n'
        .. '        kill "$GAME_PID" 2>/dev/null\n'
        .. "        sleep 3\n"
        .. "    fi\n"
        .. "done\n"
        .. 'echo "[nikke-wrapper] all $MAX_RETRIES attempts exhausted"\n'
        .. "exit 1\n",
        LAUNCH_MAX_RETRIES,
        LAUNCH_WAIT_SECONDS,
        wineprefix,
        wineserver_path
    )

    fs.write_file(wrapper_path, str.to_bytes(script)):await()

    return wrapper_path
end

------------------------------------------------- command wrapper -------------------------------------------------

local function parse_command_wrapper(wrapper: string, command: string, args: {string}, env: {[string]: string}?): (string, {string}, {[string]: string})
    if not wrapper or wrapper == "" then
        return command, args, env or {}
    end

    local parts = {}
    for part in string.gmatch(wrapper, "%S+") do
        table.insert(parts, part)
    end

    local new_command = command
    local new_args    = clone(args)
    local new_env     = env and clone(env) or {}
    local has_wrapper_command = false
    local wrapper_parts = {}

    for _, part in ipairs(parts) do
        if part == "%command%" then
            -- placeholder
        elseif string.match(part, "^[A-Z_][A-Z0-9_]*=") then
            local key, value = string.match(part, "^([^=]+)=(.*)$")
            if key and value then
                new_env[key] = value
            end
        else
            has_wrapper_command = true
            table.insert(wrapper_parts, part)
        end
    end

    if has_wrapper_command then
        new_command = wrapper_parts[1]
        local final_args = {}
        for i = 2, #wrapper_parts do
            table.insert(final_args, wrapper_parts[i])
        end
        table.insert(final_args, command)
        for _, arg in ipairs(args) do
            table.insert(final_args, arg)
        end
        new_args = final_args
    end

    return new_command, new_args, new_env
end

local function is_umu_verified(): boolean
    local umu = import_umu()

    return umu.umu.verify()
end

------------------------------------------------- settings -------------------------------------------------

local __settings = nil

local function import_settings()
    if not __settings then
        __settings = import("settings")({
            game = "nikke",
            layout = {
                launcher = {
                    title = i18n("settings_launcher_title"),
                    entries = {
                        mangohud = {
                            title = i18n("settings_mangohud_title"),
                            entry = {
                                format = "switch",
                                default = false
                            }
                        },
                        command_wrapper = {
                            title = i18n("settings_command_wrapper_title"),
                            entry = {
                                format = "text",
                                default = ""
                            }
                        }
                    }
                },
                runner = {
                    title = i18n("settings_runner_title"),
                    entries = {
                        gameid = {
                            title = i18n("settings_gameid_title"),
                            entry = {
                                format = "text",
                                default = "umu-nikke"
                            }
                        },
                        prefix = {
                            title = i18n("settings_prefix_title"),
                            entry = {
                                format = "text",
                                default = "nikke"
                            }
                        },
                        proton = {
                            title = i18n("settings_proton_title"),
                            description = i18n("settings_proton_description"),
                            reactivity = "release",
                            entry = {
                                format = "enum",
                                values = get_available_protons(),
                                default = PROTON_DEFAULT_NAME
                            }
                        }
                    }
                }
            }
        })
    end

    return __settings
end

------------------------------------------------- pipelines -------------------------------------------------

local function build_umu_pipeline()
    return {
        title = i18n("install_umu_title"),
        pipeline = {
            {
                title = i18n("install_umu_title"),
                perform = function(updater)
                    local umu = import_umu()

                    umu.umu.install(function(current: number, total: number, action: "download" | "extract")
                        updater({
                            current = current,
                            total = total,
                            format = function()
                                if action == "extract" then
                                    return i18n("extracting_progress_mb", {
                                        current = string.format("%.2f", current / 1024 / 1024),
                                        total   = string.format("%.2f", total   / 1024 / 1024)
                                    })
                                end

                                return i18n("downloading_progress_mb", {
                                    current = string.format("%.2f", current / 1024 / 1024),
                                    total   = string.format("%.2f", total   / 1024 / 1024)
                                })
                            end
                        })
                    end)
                end
            }
        }
    }
end

local function build_proton_pipeline()
    local proton_info_cache = nil

    return {
        title = i18n("install_proton_title"),
        pipeline = {
            {
                title = i18n("fetch_proton_release_title"),
                perform = function(updater)
                    updater({
                        current = 0, total = 0,
                        format = function() return i18n("checking_proton_release") end
                    })

                    local info, err = get_latest_proton_release()
                    if err or not info then
                        error("Failed to get latest Proton: " .. (err or "unknown"))
                    end

                    proton_info_cache = info

                    updater({
                        current = 1, total = 1,
                        format = function() return i18n("found_proton_release", { tag = info.tag }) end
                    })
                end
            },
            {
                title = i18n("download_proton_title"),
                perform = function(updater)
                    local archive_path = path.join(path.temp_dir(), proton_info_cache.name .. ".tar.xz")
                    local downloader_handle = downloader.create()

                    local task_handle = downloader.download(downloader_handle, {
                        url = proton_info_cache.url,
                        output_file = archive_path,
                        continue_download = true,
                        on_update = function(current: number, total: number)
                            updater({
                                current = current, total = total,
                                format = function()
                                    return i18n("downloading_progress_mb", {
                                        current = string.format("%.2f", current / 1024 / 1024),
                                        total   = string.format("%.2f", total   / 1024 / 1024)
                                    })
                                end
                            })
                        end
                    })
                    downloader.wait(task_handle)
                    downloader.close(downloader_handle)

                    proton_info_cache.archive_path = archive_path
                end
            },
            {
                title = i18n("extract_proton_title"),
                perform = function(updater)
                    if fs.exists(proton_dir_path) then
                        fs.remove_dir(proton_dir_path):await()
                    end
                    fs.create_dir(proton_dir_path):await()

                    local handle: number = archive.open(proton_info_cache.archive_path)
                    archive.extract(handle, proton_dir_path, function(current: number, total: number)
                        updater({
                            current = current, total = total,
                            format = function()
                                return i18n("extracting_progress_mb", {
                                    current = string.format("%.2f", current / 1024 / 1024),
                                    total   = string.format("%.2f", total   / 1024 / 1024)
                                })
                            end
                        })
                    end)
                    archive.close(handle)
                    fs.remove(proton_info_cache.archive_path):await()

                    -- persist the installed runner name so is_proton_installed() finds it next time
                    local settings = import_settings()
                    settings.set_property("runner.proton", proton_info_cache.name)
                end
            },
        }
    }
end

-- downloads the official NIKKE mini-installer and places it at a known path
-- inside the prefix so the user can run it manually once.
local function build_installer_pipeline(settings)
    local installer_info_cache = nil

    return {
        title = i18n("download_nikke_installer_title"),
        pipeline = {
            {
                title = i18n("fetch_installer_url_title"),
                perform = function(updater)
                    updater({
                        current = 0, total = 0,
                        format = function() return i18n("fetching_installer_version") end
                    })

                    local info, err = get_installer_info()
                    if err or not info then
                        error("Failed to get installer info: " .. (err or "unknown"))
                    end

                    installer_info_cache = info

                    updater({
                        current = 1, total = 1,
                        format = function() return i18n("found_installer", { filename = info.filename }) end
                    })
                end
            },
            {
                title = i18n("download_installer_title"),
                perform = function(updater)
                    local prefix_path = get_prefix_path(settings)
                    if not fs.exists(prefix_path) then
                        fs.create_dir(prefix_path):await()
                    end

                    local dest = path.join(path.temp_dir(), installer_info_cache.filename)
                    local downloader_handle = downloader.create()

                    local task_handle = downloader.download(downloader_handle, {
                        url = installer_info_cache.url,
                        output_file = dest,
                        continue_download = true,
                        on_update = function(current: number, total: number)
                            updater({
                                current = current, total = total,
                                format = function()
                                    return i18n("downloading_progress_mb", {
                                        current = string.format("%.2f", current / 1024 / 1024),
                                        total   = string.format("%.2f", total   / 1024 / 1024)
                                    })
                                end
                            })
                        end
                    })
                    downloader.wait(task_handle)
                    downloader.close(downloader_handle)

                    installer_info_cache.wine_path = dest
                end
            },
            {
                title = i18n("prepare_prefix_title"),
                perform = function(updater)
                    updater({
                        current = 0, total = 0,
                        format = function() return i18n("initialising_prefix") end
                    })

                    local prefix_path = get_prefix_path(settings)
                    if not fs.exists(prefix_path) then
                        fs.create_dir(prefix_path):await()
                    end

                    local proton_path = path.join(proton_dir_path, get_proton_name(settings))
                    local wine_env = {
                        PROTONPATH        = proton_path,
                        WINEPREFIX        = path.join(prefix_path, "pfx"),
                        GAMEID            = get_gameid(settings),
                        WINEDEBUG         = "",
                        PROTON_USE_WOW64  = "1"
                    }

                    local umu = import_umu()
                    if not umu.prefix.create(proton_path, prefix_path) then
                        error("Failed to initialize prefix with umu-launcher")
                    end

                    installer_info_cache.wine_env  = wine_env

                    updater({
                        current = 1, total = 1,
                        format = function() return i18n("prefix_ready") end
                    })
                end
            },
            {
                title       = i18n("run_installer_title"),
                description = i18n("installer_running"),
                perform = function()
                    local umu = import_umu()
                    umu.umu.run_installer(installer_info_cache.wine_path, installer_info_cache.wine_env)
                end
            }
        }
    }
end

------------------------------------------------- module -------------------------------------------------

return function()
    return {
        game = {
            get_launch_info = function(variant: Variant)
                if not is_umu_installed() then
                    return nil
                end

                if not is_umu_verified() then
                    return nil
                end

                local settings    = import_settings()

                if not is_proton_installed(settings) then
                    return nil
                end

                local prefix_path = get_prefix_path(settings)

                if not is_game_installed(settings) then
                    return nil
                end

                local nikke_launcher = path.join(prefix_path, "pfx", "drive_c", "NIKKE", "Launcher", "nikke_launcher.exe")
                local proton_path    = path.join(proton_dir_path, get_proton_name(settings))

                -- retry wrapper: kill wineserver + relaunch if nikke_launcher never appears
                local wrapper_path = create_launch_wrapper(prefix_path, get_proton_name(settings))

                local launch_info = {
                    binary = "/bin/bash",
                    args   = { wrapper_path, umu_binary_path, nikke_launcher },
                    env    = {
                        PROTONPATH          = proton_path,
                        WINEPREFIX          = path.join(prefix_path, "pfx"),
                        GAMEID              = get_gameid(settings),
                        WINEDEBUG           = "",
                        PROTON_USE_WOW64    = "1"
                    }
                }

                local current_binary = launch_info.binary
                local current_args   = launch_info.args or {}
                local current_env    = launch_info.env  or {}

                local command_wrapper = settings.get_property("launcher.command_wrapper")
                if command_wrapper and command_wrapper ~= "" then
                    current_binary, current_args, current_env = parse_command_wrapper(
                        command_wrapper,
                        current_binary,
                        current_args,
                        current_env
                    )
                end

                if settings.get_property("launcher.mangohud") then
                    current_binary, current_args, current_env = parse_command_wrapper(
                        "mangohud %command%",
                        current_binary,
                        current_args,
                        current_env
                    )
                end

                launch_info.binary = current_binary
                launch_info.args   = current_args
                launch_info.env    = current_env

                return launch_info
            end,

            get_actions_pipeline = function(variant: Variant)
                if not is_umu_installed() then
                    return build_umu_pipeline()
                end

                local settings = import_settings()

                if not is_proton_installed(settings) then
                    return build_proton_pipeline()
                end

                if not is_game_installed(settings) then
                    return build_installer_pipeline(settings)
                end

                return nil
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
                __settings = nil  -- force fresh proton scan each time settings are opened
                local settings = import_settings()
                return settings.get_layout(variant)
            end
        },

        tools = {
            get_buttons = function(variant: Variant)
                local settings    = import_settings()

                if not is_umu_installed() or not is_proton_installed(settings) then
                    return {}
                end

                local proton_path = path.join(proton_dir_path, get_proton_name(settings))
                local prefix_path = get_prefix_path(settings)

                local wine_env = {
                    PROTONPATH          = proton_path,
                    WINEPREFIX          = path.join(prefix_path, "pfx"),
                    GAMEID              = get_gameid(settings),
                    WINEDEBUG           = "",
                    PROTON_USE_WOW64    = "1"
                }

                return {
                    {
                        title       = i18n("tool_winecfg_title"),
                        description = i18n("tool_winecfg_description"),
                        callback    = function()
                            local umu = import_umu()
                            umu.tools.open_winecfg(wine_env)
                        end
                    },

                    {
                        title       = i18n("tool_wineconsole_title"),
                        description = i18n("tool_wineconsole_description"),
                        callback    = function()
                            local umu = import_umu()
                            umu.tools.open_wineconsole(wine_env)
                        end
                    },

                    {
                        title       = i18n("tool_kill_wineserver_title"),
                        description = i18n("tool_kill_wineserver_description"),
                        callback    = function()
                            local umu = import_umu()
                            umu.prefix.kill_wineserver(proton_path, prefix_path)
                        end
                    },

                    {
                        title       = i18n("tool_open_folder_title"),
                        description = i18n("tool_open_folder_description"),
                        callback    = function()
                            local umu = import_umu()
                            umu.tools.open_folder(data_dir_path)
                        end
                    }
                }
            end
        }
    }
end
