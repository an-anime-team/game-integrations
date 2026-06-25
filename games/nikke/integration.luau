-- GODDESS OF VICTORY: NIKKE integration v0.3.0
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

type GameVariant = {
    platform: string,
    edition: string
}

----------------------------- constants -----------------------------

local NIKKE_SITE_BASE = "https://nikke-en.com"
local NIKKE_ASSETS_JS = `{NIKKE_SITE_BASE}/assets/aix-18872c9c.js`

-- umu-launcher game identifier and lua-proton prefix folder name.
local GAME_ID: string = "umu-nikke"
local PREFIX_NAME: string = "goddess_of_victory_nikke"

-- launch retry: seconds to wait before checking --ProductName=nikke_launcher
local LAUNCH_MAX_RETRIES  = 10
local LAUNCH_WAIT_SECONDS = 8

----------------------------- paths -----------------------------

local data_dir_path: string = path.persist_dir("goddess_of_victory_nikke")

-- lua-proton keeps proton versions and prefixes in its own persistent dir.
local lua_proton_dir_path: string = path.persist_dir("lua-proton")
local lua_proton_prefix_path: string = path.join(lua_proton_dir_path, "prefixes", PREFIX_NAME)

-- Legacy (pre lua-proton) locations kept around only for migration.
local legacy_prefix_path: string = path.join(data_dir_path, "prefix", "nikke")
local legacy_proton_path: string = path.join(data_dir_path, "proton")
local legacy_umu_binary_path: string = path.join(data_dir_path, "umu-run")

----------------------------- translations -----------------------------

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

----------------------------- migration -----------------------------

-- Silently move an existing pre lua-proton install into the layout used by the
-- lua-proton library, then drop the now-orphaned proton/umu files.
local function migrate_legacy_install()
    -- Move the existing wine prefix (the installed game) into lua-proton's
    -- prefixes directory so it keeps being detected without reinstalling.
    if fs.exists(path.join(legacy_prefix_path, "pfx"))
        and not fs.exists(path.join(lua_proton_prefix_path, "pfx"))
    then
        local prefixes_dir = path.join(lua_proton_dir_path, "prefixes")

        if not fs.exists(prefixes_dir) then
            fs.create_dir(prefixes_dir):await()
        end

        fs.move(legacy_prefix_path, lua_proton_prefix_path):await()
    end

    -- Remove the leftover legacy prefix folder (now empty) if the move happened.
    local legacy_prefix_parent = path.join(data_dir_path, "prefix")

    if fs.exists(legacy_prefix_parent) and not fs.exists(legacy_prefix_path) then
        fs.remove_dir(legacy_prefix_parent):await()
    end

    -- Drop the legacy proton builds (lua-proton manages its own versions).
    if fs.exists(legacy_proton_path) then
        fs.remove_dir(legacy_proton_path):await()
    end

    -- Drop the legacy umu-run binary (lua-proton ships its own).
    if fs.exists(legacy_umu_binary_path) then
        fs.remove(legacy_umu_binary_path):await()
    end
end

----------------------------- game detection -----------------------------

local function get_nikke_launcher_path(): string
    return path.join(lua_proton_prefix_path, "pfx", "drive_c", "NIKKE", "Launcher", "nikke_launcher.exe")
end

local function is_game_installed(): boolean
    return fs.exists(get_nikke_launcher_path())
end

----------------------------- game installer -----------------------------

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

----------------------------- launch wrapper -----------------------------

-- Writes a bash script that retries the launch when nikke_launcher never
-- appears.
local function create_launch_wrapper(wineprefix: string, proton_path: string): string
    local wrapper_path    = path.join(data_dir_path, "nikke-launch-wrapper.sh")
    local wineserver_path = path.join(proton_path, "files", "bin", "wineserver")

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

    if not fs.exists(data_dir_path) then
        fs.create_dir(data_dir_path):await()
    end

    fs.write_file(wrapper_path, str.to_bytes(script)):await()

    return wrapper_path
end

----------------------------- command wrapper -----------------------------

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

----------------------------- settings -----------------------------

local __settings = nil

local function get_settings_layout()
    if not __settings then
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
                }
            }
        })
    end

    return __settings
end

----------------------------- pipelines -----------------------------

type PipelineUpdater = ({ current: number, total: number, format: (() -> string) | nil }) -> ()

-- Download the official NIKKE installer and run it inside the proton prefix so
-- the user can complete the installation once.
local function get_game_installer_pipeline(
    lua_proton: any,
    installer_url: string,
    installer_filename: string
)
    local installer_path = path.join(path.temp_dir(), installer_filename)

    return {
        title = i18n("download_nikke_installer_title"),
        pipeline = {
            {
                title = i18n("download_installer_title"),
                perform = function(updater: PipelineUpdater)
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
                title = i18n("run_installer_title"),
                description = i18n("installer_running"),
                perform = function()
                    -- The proton prefix is created by lua-proton's actions
                    -- pipeline, so by this point wrapping the installer command
                    -- gives us a ready-to-run umu-launcher invocation.
                    local launch_info = lua_proton.game.wrap_launch_info({
                        binary = installer_path,
                        args = {},
                        env = {
                            PROTON_USE_WOW64 = "1"
                        }
                    })

                    if not launch_info then
                        return
                    end

                    local handle = process.open(launch_info.binary, launch_info.args, launch_info.env)

                    process.wait(handle)
                end
            }
        }
    }
end

----------------------------- module -----------------------------

return function()
    local iter = import("iterable")

    -- Move an existing pre lua-proton install into the new layout, if any.
    migrate_legacy_install()

    local settings = get_settings_layout()

    local lua_proton = import("lua-proton").proton({
        umu_launcher = {
            game_id = GAME_ID
        },

        prefix = {
            name = PREFIX_NAME
        },

        settings = {
            get_property = settings.get_property,
            set_property = settings.set_property
        }
    })

    return {
        game = {
            get_launch_info = function(
                variant: GameVariant
            ): { binary: string, args: { string }, env: { [string]: string } }?
                -- Check if the game is installed.
                if not is_game_installed() then
                    return nil
                end

                -- Try to obtain game launch info from the lua-proton library.
                -- It will return nil if selected proton is not available.
                local wrapped = lua_proton.game.wrap_launch_info({
                    binary = get_nikke_launcher_path(),
                    args = {},
                    env = {
                        PROTON_USE_WOW64 = "1"
                    }
                })

                if not wrapped then
                    return nil
                end

                -- retry wrapper: kill wineserver + relaunch if nikke_launcher
                -- never appears.
                local wrapper_path = create_launch_wrapper(
                    wrapped.env["WINEPREFIX"],
                    wrapped.env["PROTONPATH"]
                )

                local launch_info = {
                    binary = "bash",
                    args = { wrapper_path, wrapped.binary },
                    env = wrapped.env
                }

                for _, arg in ipairs(wrapped.args) do
                    table.insert(launch_info.args, arg)
                end

                -- Apply user-defined command wrapper.
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

                -- Wrap game launch command with steam-run for NixOS hosts.
                local nixos_wrapper = import("nixos-command-wrapper")

                return nixos_wrapper(launch_info)
            end,

            get_actions_pipeline = function(variant: GameVariant): any
                -- Install/update umu-launcher, proton and the prefix.
                local proton_pipeline = lua_proton.game.get_actions_pipeline()

                if proton_pipeline then
                    return proton_pipeline
                end

                -- If the game is not installed - then return a pipeline to
                -- install it.
                if not is_game_installed() then
                    local result, installer_info = pcall(get_installer_info)

                    if not result then
                        return nil
                    end

                    return get_game_installer_pipeline(
                        lua_proton,
                        installer_info.url,
                        installer_info.filename
                    )
                end

                return nil
            end
        },

        components = {
            get_layout = function()
                return {
                    {
                        entries = {
                            {
                                name = "launcher",
                                title = i18n("settings_launcher_title"),
                                locked = true
                            }
                        }
                    }
                }
            end,

            get_enabled = function() return true end,
            set_enabled = function() end,

            uninstall = function(variant: GameVariant, component: string)
                if component == "launcher" then
                    if fs.exists(data_dir_path) then
                        fs.remove_dir(data_dir_path):await()
                    end

                    -- Remove this game's proton prefix while keeping the shared
                    -- proton versions intact.
                    if fs.exists(lua_proton_prefix_path) then
                        fs.remove_dir(lua_proton_prefix_path):await()
                    end
                end
            end
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
