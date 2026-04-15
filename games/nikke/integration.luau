-- GODDESS OF VICTORY: NIKKE integration v0.1.0
-- Copyright (C) 2026 NelloKudo <marshnelloosu@gmail.com>
--                    Nikita Podvirnyi <krypt0nn@vk.com>
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

function import(...)
    return (load("import").value)(...)
end

type Variant = {
    platform: string,
    edition: string
}

type ProtonBuildInfo = {
    name: string,
    title: string,
    url: string,
    path: string
}

------------------------------------------------- constants -------------------------------------------------

local NIKKE_SITE_BASE = "https://nikke-en.com"
local NIKKE_ASSETS_JS = `{NIKKE_SITE_BASE}/assets/aix-18872c9c.js`

-- launch retry: seconds to wait before checking --ProductName=nikke_launcher
local LAUNCH_MAX_RETRIES  = 10
local LAUNCH_WAIT_SECONDS = 8

------------------------------------------------- paths -------------------------------------------------

local data_dir_path: string = path.persist_dir("goddess_of_victory_nikke")

local umu_binary_path: string = path.join(data_dir_path, "umu-run")
local proton_builds_path: string = path.join(data_dir_path, "proton")
local proton_prefix_path: string = path.join(data_dir_path, "prefix")

------------------------------------------------- imports -------------------------------------------------

local __i18n = nil
local __umu = nil

local function i18n(...)
    if not __i18n then
        local locales = import("locales")

        locales = fs.read_file(locales):await()
        locales = str.decode("toml", str.from_bytes(locales))

        __i18n = import("i18n").i18n(locales)
    end

    return (__i18n)(...)
end

local function import_umu()
    if not __umu then
        __umu = import("umu_launcher")(umu_binary_path)
    end

    return __umu
end

------------------------------------------------- component management -------------------------------------------------

local __proton_builds = nil

local function list_proton_builds(): { ProtonBuildInfo }
    if not __proton_builds then
        local src = import("dwproton-src")

        local builds = fs.read_file(src):await()

        __proton_builds = str.decode("json", str.from_bytes(builds))
    end

    return clone(__proton_builds)
end

local function get_latest_proton_build(): ProtonBuildInfo
    return list_proton_builds()[1]
end

local function check_proton_build_installed(name: string): boolean
    return fs.exists(path.join(proton_builds_path, name, "files", "bin", "wine64"))
end

------------------------------------------------- game detection -------------------------------------------------

local function get_prefix_path(): string
    return path.join(proton_prefix_path, "nikke")
end

local function is_game_installed(): boolean
    local nikke_launcher = path.join(get_prefix_path(), "pfx", "drive_c", "NIKKE", "Launcher", "nikke_launcher.exe")

    return fs.exists(nikke_launcher)
end

------------------------------------------------- game installer -------------------------------------------------

-- Fetch the JS bundle and extracts the miniloader download url
local function get_installer_info(): { url: string, filename: string }
    local resp = http.fetch(NIKKE_ASSETS_JS, { method = "get" }):await()

    if not resp.is_ok then
        error(`failed to fetch nikke installer JS asset: {resp.status}`)
    end

    local body = str.from_bytes(resp.body)

    local loader_path = string.match(body, '"(/nikkeminiloader[^"]+%.exe)"')

    if not loader_path then
        error(`couldn't extract nikke miniloader path from JS asset`)
    end

    return {
        url = `{NIKKE_SITE_BASE}/{loader_path:gsub("^/+", "")}`,
        filename = string.match(loader_path, "/([^/]+)$") or loader_path
    }
end

------------------------------------------------- launch wrapper -------------------------------------------------

-- Writes a bash script that retries the launch when nikke_launcher never
-- appears.
local function create_launch_wrapper(prefix_path: string, proton_name: string): string
    local wrapper_path    = path.join(data_dir_path, "nikke-launch-wrapper.sh")
    local wineserver_path = path.join(proton_builds_path, proton_name, "files", "bin", "wineserver")
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

local function parse_command_wrapper(
    wrapper: string,
    binary: string,
    args: { string },
    env: { [string]: string }?
): { binary: string, args: { string }, env: { [string]: string } }
    if not wrapper or wrapper == "" then
        return {
            binary = binary,
            args = args,
            env = env or {}
        }
    end

    local parts = {}

    for part in string.gmatch(wrapper, "%S+") do
        table.insert(parts, part)
    end

    local new_command = binary
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

        table.insert(final_args, binary)

        for _, arg in ipairs(args) do
            table.insert(final_args, arg)
        end

        new_args = final_args
    end

    return {
        binary = new_command,
        args = new_args,
        env = new_env
    }
end

------------------------------------------------- settings -------------------------------------------------

local __settings = nil

local function import_settings(refresh: boolean?)
    if not __settings or refresh == true then
        local proton_builds = {}

        for _, info in ipairs(list_proton_builds()) do
            proton_builds[info.name] = info.title
        end

        __settings = import("settings")({
            game = "goddess_of_victory_nikke",
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
                proton = {
                    title = i18n("settings_runner_title"),
                    entries = {
                        build_name = {
                            title = i18n("settings_proton_title"),
                            description = i18n("settings_proton_description"),
                            reactivity = "release",
                            entry = {
                                format = "enum",
                                values = proton_builds,
                                default = get_latest_proton_build().name
                            }
                        }
                    }
                }
            }
        })
    end

    return __settings
end

local function get_selected_proton_build_name(): string?
    return import_settings().get_property("proton.build_name")
end

local function set_selected_proton_build_name(name: string)
    import_settings().set_property("proton.build_name", name)
end

------------------------------------------------- pipelines -------------------------------------------------

type PipelineUpdater = ({ current: number, total: number, format: (() -> string) | nil }) -> ()

type PipelineAction = {
    title: string | { [string]: string },
    description: string | { [string]: string } | nil,
    perform: any -- (updater: PipelineUpdater?) -> ()
}

type ActionsPipeline = {
    title: string | { [string]: string },
    description: string | { [string]: string } | nil,
    pipeline: { PipelineAction }
}

local function get_install_umu_pipeline(): ActionsPipeline
    return {
        title = i18n("install_umu_title"),
        pipeline = {
            {
                title = i18n("install_umu_title"),
                perform = function(updater: PipelineUpdater)
                    local umu = import_umu()

                    umu.umu.install(function(current: number, total: number, action: "download" | "extract")
                        updater({
                            current = current,
                            total = total,
                            format = function()
                                local current: string = string.format("%.2f", current / 1024 / 1024)
                                local total: string   = string.format("%.2f", total   / 1024 / 1024)

                                if action == "download" then
                                    return i18n("downloading_progress_mb", {
                                        current = current,
                                        total   = total
                                    })
                                elseif action == "extract" then
                                    return i18n("extracting_progress_mb", {
                                        current = current,
                                        total   = total
                                    })
                                else
                                    return i18n("processing_progress_mb", {
                                        current = current,
                                        total   = total
                                    })
                                end
                            end
                        })
                    end)
                end
            }
        }
    }
end

local function get_install_proton_build_pipeline(name: string?): ActionsPipeline
    local info = get_latest_proton_build()

    if typeof(name) == "string" then
        local iter = import("iterable")

        local found_info = iter(list_proton_builds())
            .find(function(info: ProtonBuildInfo)
                return info.name == name
            end)

        if found_info or not info then
            info = found_info
        end
    end

    local archive_path: string = path.join(path.temp_dir(), "goddes_of_victory_nikke", `{info.name}.tar.xz`)
    local extract_path: string = path.join(path.temp_dir(), "goddes_of_victory_nikke", info.name)
    local final_path: string   = path.join(proton_builds_path, info.name)

    return {
        title = i18n("install_proton_title"),
        pipeline = {
            {
                title = i18n("download_proton_title"),
                perform = function(updater: PipelineUpdater)
                    local downloader_handle = downloader.create()

                    local task_handle = downloader.download(downloader_handle, {
                        url = info.url,
                        output_file = archive_path,
                        continue_download = true,
                        on_update = function(current: number, total: number)
                            updater({
                                current = current,
                                total = total,
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
                end
            },
            {
                title = i18n("extract_proton_title"),
                perform = function(updater: PipelineUpdater)
                    if not fs.exists(extract_path) then
                        fs.create_dir(extract_path):await()
                    end

                    local archive_handle = archive.open(archive_path)

                    archive.extract(
                        archive_handle,
                        extract_path,
                        function(current: number, total: number)
                            updater({
                                current = current,
                                total = total,
                                format = function()
                                    return i18n("extracting_progress_mb", {
                                        current = string.format("%.2f", current / 1024 / 1024),
                                        total   = string.format("%.2f", total   / 1024 / 1024)
                                    })
                                end
                            })
                        end
                    )

                    archive.close(archive_handle)

                    fs.remove(archive_path):await()
                    fs.move(path.join(extract_path, info.path), final_path):await()
                    fs.remove(extract_path):await()

                    set_selected_proton_build_name(info.name)
                end
            }
        }
    }
end

-- Download the official NIKKE installer and place it at a known path inside the
-- wine prefix so the user can run it manually once
local function get_game_installer_pipeline(
    installer_url: string,
    installer_filename: string
): ActionsPipeline
    local installer_path = path.join(path.temp_dir(), installer_filename)

    local wine_env = {
        GAMEID           = "umu-nikke",
        WINEDEBUG        = "",
        PROTON_USE_WOW64 = "1"
    }

    return {
        title = i18n("download_nikke_installer_title"),
        pipeline = {
            {
                title = i18n("download_installer_title"),
                perform = function(updater)
                    local prefix_path = get_prefix_path()

                    if not fs.exists(prefix_path) then
                        fs.create_dir(prefix_path):await()
                    end

                    local downloader_handle = downloader.create()

                    local task_handle = downloader.download(downloader_handle, {
                        url = installer_url,
                        output_file = installer_path,
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
                end
            },
            {
                title = i18n("prepare_prefix_title"),
                perform = function(updater)
                    local prefix_path = get_prefix_path()

                    if not fs.exists(prefix_path) then
                        fs.create_dir(prefix_path):await()
                    end

                    local proton_name = get_selected_proton_build_name()
                    local proton_path = path.join(proton_builds_path, proton_name)

                    wine_env["PROTONPATH"] = proton_path
                    wine_env["WINEPREFIX"] = path.join(prefix_path, "pfx")

                    local umu = import_umu()

                    if not umu.umu.verify() then
                        error("umu-launcher binary is invalid")
                    end

                    if not umu.prefix.create(proton_path, prefix_path) then
                        error("failed to initialize prefix with umu-launcher")
                    end
                end
            },
            {
                title       = i18n("run_installer_title"),
                description = i18n("installer_running"),
                perform = function()
                    local umu = import_umu()

                    local info = umu.umu.wrap({
                        binary = installer_path,
                        args   = {},
                        env    = wine_env
                    })

                    if not umu.umu.verify() then
                        error("umu-launcher binary is invalid")
                    end

                    local handle = process.open(info.binary, info.args, info.env)

                    process.wait(handle)
                end
            }
        }
    }
end

------------------------------------------------- module -------------------------------------------------

return function()
    return {
        game = {
            get_launch_info = function(
                variant: Variant
            ): { binary: string, args: { string }, env: { [string]: string } }?
                local umu_launcher = import_umu()

                if not umu_launcher.umu.verify() then
                    return nil
                end

                local settings = import_settings()
                local selected_proton_build = get_selected_proton_build_name()

                if not selected_proton_build or not check_proton_build_installed(selected_proton_build) then
                    return nil
                end

                if not is_game_installed() then
                    return nil
                end

                local prefix_path    = get_prefix_path()
                local nikke_launcher = path.join(prefix_path, "pfx", "drive_c", "NIKKE", "Launcher", "nikke_launcher.exe")
                local proton_path    = path.join(proton_builds_path, selected_proton_build)

                -- retry wrapper: kill wineserver + relaunch if nikke_launcher never appears
                local wrapper_path = create_launch_wrapper(prefix_path, selected_proton_build)

                local launch_info = {
                    binary = "bash",
                    args = {
                        wrapper_path,
                        umu_binary_path,
                        nikke_launcher
                    },
                    env = {
                        PROTONPATH       = proton_path,
                        WINEPREFIX       = path.join(prefix_path, "pfx"),
                        GAMEID           = "umu-nikke",
                        WINEDEBUG        = "",
                        PROTON_USE_WOW64 = "1"
                    }
                }

                local command_wrapper = settings.get_property("launcher.command_wrapper")

                if command_wrapper and command_wrapper ~= "" then
                    launch_info = parse_command_wrapper(
                        command_wrapper,
                        launch_info.binary,
                        launch_info.args,
                        launch_info.env
                    )
                end

                if settings.get_property("launcher.mangohud") then
                    launch_info.env["MANGOHUD"] = "1"
                end

                return launch_info
            end,

            get_actions_pipeline = function(variant: Variant): any
                local umu_launcher = import_umu()

                local umu_status, umu_reason = umu_launcher.umu.verify()

                if not umu_status then
                    if umu_reason == "invalid_hash" then
                        return get_install_umu_pipeline()
                    elseif umu_reason == "missing_python3_binary" then
                        portal.toast({ message = i18n("umu_launcher_missing_python3") })
                    elseif umu_reason == "missing_bwrap_binary" then
                        portal.toast({ message = i18n("umu_launcher_missing_bwrap") })
                    else
                        portal.toast({ message = i18n("umu_launcher_invalid_status") })
                    end

                    return nil
                end

                -- Read selected proton build name
                local selected_proton_build = get_selected_proton_build_name()

                -- If none is selected or selected build is not installed then
                -- return a pipeline to download a new proton build
                if not selected_proton_build or not check_proton_build_installed(selected_proton_build) then
                    return get_install_proton_build_pipeline(selected_proton_build)
                end

                -- If some build is selected then try to find it in installed
                -- proton builds list
                local iter = import("iterable")

                local is_build_available: boolean = iter(list_proton_builds())
                    .any(function(info: ProtonBuildInfo)
                        return info.name == selected_proton_build
                    end)

                -- If it's not found - then return a pipeline to install the
                -- latest available one
                if not is_build_available then
                    return get_install_proton_build_pipeline()
                end

                -- If the game is not installed - then return a pipeline to
                -- install it.
                if not is_game_installed() then
                    local result, installer_info = pcall(get_installer_info)

                    if not result then
                        -- Show error message here?
                        return nil
                    end

                    return get_game_installer_pipeline(
                        installer_info.url,
                        installer_info.filename
                    )
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
                local settings = import_settings(true)

                return settings.get_layout(variant)
            end
        }
    }
end
