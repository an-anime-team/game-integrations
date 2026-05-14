-- Neverness to Everness integration v0.0.0
-- Copyright (C) 2026 Dylan Donnell <greenicedtea@tutanota.com>
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

local INSTALLER_URLS = {
    global   = "https://ntecdn2.perfectworld.com/clientRes/installer-Global/YH_Singapore_common_setup_1.0.6.0423_20260424.exe",
    bilibili = "https://pkg.biligame.com/games/NevernessToEverness_setup_bilibili/664512/NevernessToEverness_setup_bilibili.exe",
    china    = "https://yhcdn1.wmupd.com/clientRes/OBInstaller/YH_common_setup_1.0.4.0415_20260416.exe"
}

local INSTALLER_FILENAMES = {
    global   = "YH_Singapore_common_setup_1.0.6.0423_20260424.exe",
    bilibili = "NevernessToEverness_setup_bilibili.exe",
    china    = "YH_common_setup_1.0.4.0415_20260416.exe"
}

local LAUNCHER_EXE_NAMES = {
    global   = "NTEGlobalLauncher.exe",
    bilibili = "NTELauncher.exe",
    china    = "NTELauncher.exe"
}

------------------------------------------------- paths -------------------------------------------------

local data_dir_path: string = path.persist_dir("neverness_to_everness")

local umu_binary_path: string = path.join(data_dir_path, "umu-run")
local proton_builds_path: string = path.join(data_dir_path, "proton")
local proton_prefix_path: string = path.join(data_dir_path, "prefix")

local function get_prefix_path(edition: string): string
    return path.join(proton_prefix_path, edition)
end

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

local function check_umu_ready(): (boolean, string?)
    local umu = import_umu()
    local status, reason = umu.umu.verify()

    if not status then
        return false, reason
    end

    return true, nil
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
    local proton_dir = path.join(proton_builds_path, name)
    local wine64_path = path.join(proton_dir, "files", "bin", "wine64")
    local wine_path = path.join(proton_dir, "files", "bin", "wine")

    return fs.exists(wine64_path) or fs.exists(wine_path)
end

------------------------------------------------- game detection -------------------------------------------------

local function get_launcher_exe_path(edition: string): string
    return path.join(get_prefix_path(edition), "pfx", "drive_c", "Program Files", "Neverness To Everness", LAUNCHER_EXE_NAMES[edition] or LAUNCHER_EXE_NAMES.global)
end

local function is_game_installed(edition: string): boolean
    local exe = get_launcher_exe_path(edition)
    local ok = fs.exists(exe)
    return ok
end

------------------------------------------------- game installer -------------------------------------------------

local function get_installer_info(edition: string): { url: string, filename: string }
    edition = edition or "global"

    return {
        url = INSTALLER_URLS[edition],
        filename = INSTALLER_FILENAMES[edition]
    }
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
            game = "neverness_to_everness",
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
    perform: any
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

    local archive_path: string = path.join(path.temp_dir(), "neverness_to_everness", `{info.name}.tar.xz`)
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
                    if not fs.exists(proton_builds_path) then
                        fs.create_dir(proton_builds_path):await()
                    end

                    if fs.exists(final_path) then
                        fs.remove(final_path):await()
                    end

                    local archive_handle = archive.open(archive_path)

                    archive.extract(
                        archive_handle,
                        proton_builds_path,
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

                    if fs.exists(path.join(proton_builds_path, info.path)) then
                        fs.move(path.join(proton_builds_path, info.path), final_path):await()
                    end

                    set_selected_proton_build_name(info.name)
                end
            }
        }
    }
end

local function get_game_installer_pipeline(edition: string): ActionsPipeline
    edition = edition or "global"
    local info = get_installer_info(edition)
    local installer_path = path.join(path.temp_dir(), info.filename)

    local wine_env = {
        GAMEID           = `umu-nte-{edition}`,
        WINEDEBUG        = "",
        PROTON_USE_WOW64 = "1"
    }

    return {
        title = i18n("download_nte_installer_title"),
        pipeline = {
            {
                title = i18n("download_installer_title"),
                perform = function(updater)
                    local prefix_path = get_prefix_path(edition)

                    if not fs.exists(prefix_path) then
                        fs.create_dir(prefix_path):await()
                    end

                    local downloader_handle = downloader.create()

                    local task_handle = downloader.download(downloader_handle, {
                        url = info.url,
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
                    local prefix_path = get_prefix_path(edition)

                    if not fs.exists(prefix_path) then
                        fs.create_dir(prefix_path):await()
                    end

                    local proton_name = get_selected_proton_build_name()
                    local proton_path = path.join(proton_builds_path, proton_name)

                    wine_env["PROTONPATH"] = proton_path
                    wine_env["WINEPREFIX"] = path.join(prefix_path, "pfx")
                    wine_env["PROTON_SET_GAME_DRIVE"] = "0"

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
                title = i18n("run_installer_title"),
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

return {
    game = {
        get_editions = function(platform: string)
            return {
                { name = "global",   title = i18n("global_game_edition") },
                { name = "bilibili", title = i18n("bilibili_game_edition") },
                { name = "china",    title = i18n("china_game_edition") }
            }
        end,

        get_status = function(variant: Variant): string
            local edition = variant.edition or "global"

            local ok, reason = check_umu_ready()
            if not ok then
                if reason == "invalid_hash" then
                    return "not-installed"
                end

                return "not-installed"
            end

            local selected_proton_build = get_selected_proton_build_name()

            if not selected_proton_build or not check_proton_build_installed(selected_proton_build) then
                return "not-installed"
            end

            if not is_game_installed(edition) then
                return "not-installed"
            end

            return "installed"
        end,

        get_actions_pipeline = function(variant: Variant): any
            local edition = variant.edition or "global"

            local ok, reason = check_umu_ready()
            if not ok then
                if reason == "invalid_hash" then
                    return get_install_umu_pipeline()
                elseif reason == "missing_python3_binary" then
                    portal.toast({ message = i18n("umu_launcher_missing_python3") })
                elseif reason == "missing_bwrap_binary" then
                    portal.toast({ message = i18n("umu_launcher_missing_bwrap") })
                else
                    portal.toast({ message = i18n("umu_launcher_invalid_status") })
                end

                return nil
            end

            local selected_proton_build = get_selected_proton_build_name()

            if not selected_proton_build or not check_proton_build_installed(selected_proton_build) then
                return get_install_proton_build_pipeline(selected_proton_build)
            end

            local iter = import("iterable")

            local is_build_available: boolean = iter(list_proton_builds())
                .any(function(info: ProtonBuildInfo)
                    return info.name == selected_proton_build
                end)

            if not is_build_available then
                return get_install_proton_build_pipeline()
            end

            if not is_game_installed(edition) then
                return get_game_installer_pipeline(edition)
            end

            return nil
        end,

        get_launch_info = function(variant: Variant): any
            local edition = variant.edition or "global"

            local ok, _umu_err = check_umu_ready()
            if not ok then
                return nil
            end

            local settings = import_settings()
            local selected_proton_build = get_selected_proton_build_name()

            if not selected_proton_build or not check_proton_build_installed(selected_proton_build) then
                return nil
            end

            if not is_game_installed(edition) then
                return nil
            end

            local prefix_path    = get_prefix_path(edition)
            local launcher_exe   = get_launcher_exe_path(edition)
            local proton_path    = path.join(proton_builds_path, selected_proton_build)

            local launch_info = {
                binary = umu_binary_path,
                args = {
                    launcher_exe
                },
                env = {
                    PROTONPATH       = proton_path,
                    WINEPREFIX       = path.join(prefix_path, "pfx"),
                    GAMEID           = `umu-nte-{edition}`,
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
