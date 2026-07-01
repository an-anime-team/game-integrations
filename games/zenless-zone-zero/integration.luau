-- ZZZ integration v0.2.4
-- Copyright (C) 2026  Nikita Podvirnyi <krypt0nn@vk.com>
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

local DATA_DIR: string = path.persist_dir("zenless_zone_zero")

local GAME_DIR: { [GameEdition]: string } = {
    global = path.join(DATA_DIR, "global_game_files"),
    china = path.join(DATA_DIR, "china_game_files")
}

local GAME_BINARY: { [GameEdition]: string } = {
    global = path.join(GAME_DIR["global"], "ZenlessZoneZero.exe"),
    china = path.join(GAME_DIR["china"], "ZenlessZoneZero.exe")
}

local GAME_VERSION_PATH: { [GameEdition]: string } = {
    global = path.join(GAME_DIR["global"], ".version"),
    china = path.join(GAME_DIR["china"], ".version")
}

local SOPHON_GAME_ID: { [GameEdition]: string } = {
    global = "U5hbdsT9W7", -- nap_global
    china = "x6znKlJ0xK"   -- nap_cn
}

type GameEdition = "global" | "china"

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

local function get_settings_layout()
    if not __settings then
        __settings = import("settings")({
            game = "zenless_zone_zero",
            layout = {
                game = {
                    title = i18n("game"),
                    entries = {
                        timeout_fix = {
                            title = i18n("game_timeout_fix_title"),
                            description = i18n("game_timeout_fix_description"),
                            reactivity = "none",
                            entry = {
                                format = "switch",
                                default = false
                            }
                        }
                    }
                },
                sophon_tools = {
                    title = i18n("sophon_tools_settings_title"),
                    entries = {
                        user_agent = {
                            title = i18n("sophon_tools_settings_user_agent_title"),
                            description = i18n("sophon_tools_settings_user_agent_description"),
                            reactivity = "none",
                            entry = {
                                format = "text",
                                default = ""
                            }
                        },
                        proxy = {
                            title = i18n("sophon_tools_settings_proxy_title"),
                            description = i18n("sophon_tools_settings_proxy_description"),
                            reactivity = "none",
                            entry = {
                                format = "text",
                                default = ""
                            }
                        },
                        threads = {
                            title = i18n("sophon_tools_settings_threads_title"),
                            description = i18n("sophon_tools_settings_threads_description"),
                            reactivity = "none",
                            entry = {
                                format = "number",
                                min = 0,
                                max = 32,
                                step = 1,
                                default = 0
                            }
                        },
                        target_memory_usage = {
                            title = i18n("sophon_tools_settings_target_memory_usage_title"),
                            description = i18n("sophon_tools_settings_target_memory_usage_description"),
                            reactivity = "none",
                            entry = {
                                format = "number",
                                min = 64,
                                max = 2048,
                                step = 64,
                                default = 256
                            }
                        },
                        fast_verify = {
                            title = i18n("sophon_tools_settings_fast_verify_title"),
                            description = i18n("sophon_tools_settings_fast_verify_description"),
                            reactivity = "none",
                            entry = {
                                format = "switch",
                                default = false
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

local function get_update_sophon_tools_pipeline(sophon_tools: any)
    return {
        title = i18n("download_sophon_tools_title"),
        pipeline = {
            {
                title = i18n("download_sophon_tools_title"),

                perform = function(updater)
                    sophon_tools.tool.download(function(current: number, total: number)
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
                    end)
                end
            }
        }
    }
end

local function get_download_game_pipeline(
    sophon_tools: any,
    options: {
        edition: GameEdition;
        threads: number?;
        target_memory_usage: number?;
        fast_verify: boolean?,
        user_agent: string?;
        proxy: string?;
    }
)
    local future = nil

    local progress = {
        fetch_info = false,
        verify = { current = 0, total = 0, finished = false },
        download = { current = 0, total = 0, finished = false }
    }

    return {
        title = i18n("install_game_title"),
        pipeline = {
            {
                title = i18n("fetch_download_info_title"),

                perform = function()
                    local options = {
                        game_id = SOPHON_GAME_ID[options.edition],
                        game_dir = GAME_DIR[options.edition],

                        threads = options.threads,
                        target_memory_usage = options.target_memory_usage,

                        verify_before_downloading =
                            if options.fast_verify == true then "fast" else "full",

                        api = {
                            region = options.edition
                        },

                        network = {
                            user_agent = options.user_agent,
                            proxy = options.proxy
                        }
                    }

                    future = sophon_tools.game.download(options, function(msg)
                        progress.fetch_info = true

                        if msg.type == "verify" then
                            progress.verify.current = msg.current
                            progress.verify.total = msg.total
                        elseif msg.type == "download" then
                            progress.verify.finished = true

                            progress.download.current = msg.current
                            progress.download.total = msg.total

                            if msg.current == msg.total then
                                progress.download.finished = true
                            end
                        end
                    end)

                    while not progress.fetch_info and future do
                        local status, _ = future:poll()

                        if status then
                            future = nil

                            progress.fetch_info = true
                            progress.verify.finished = true
                            progress.download.finished = true
                        end
                    end
                end
            },
            {
                title = i18n("verify_available_files_title"),

                before = function()
                    return not progress.verify.finished and future
                end,

                perform = function(updater: any)
                    while not progress.verify.finished and future do
                        local status, _ = future:poll()

                        updater({
                            current = progress.verify.current,
                            total = progress.verify.total,
                            format = function()
                                return i18n("verifying_progress_gb", {
                                    current = string.format("%.2f", progress.verify.current / 1024 / 1024 / 1024),
                                    total = string.format("%.2f", progress.verify.total / 1024 / 1024 / 1024)
                                })
                            end
                        })

                        if status then
                            future = nil

                            progress.fetch_info = true
                            progress.verify.finished = true
                            progress.download.finished = true
                        end
                    end
                end
            },
            {
                title = i18n("download_new_files_title"),

                before = function()
                    return not progress.download.finished and future
                end,

                perform = function(updater: any)
                    while not progress.download.finished and future do
                        local status, _ = future:poll()

                        updater({
                            current = progress.download.current,
                            total = progress.download.total,
                            format = function()
                                return i18n("downloading_progress_gb", {
                                    current = string.format("%.2f", progress.download.current / 1024 / 1024 / 1024),
                                    total = string.format("%.2f", progress.download.total / 1024 / 1024 / 1024)
                                })
                            end
                        })

                        if status then
                            future = nil

                            progress.fetch_info = true
                            progress.verify.finished = true
                            progress.download.finished = true
                        end
                    end
                end
            },
            {
                title = i18n("finalize_download_title"),

                perform = function()
                    if future then
                        future:await()
                    end

                    local game_info = sophon_tools.game.detect({
                        game_dir = GAME_DIR[options.edition],
                        network = {
                            user_agent = options.user_agent,
                            proxy = options.proxy
                        }
                    }):await()

                    if game_info and game_info.version then
                        game_version_write(options.edition, game_info.version)
                    end
                end
            }
        }
    }
end

local function get_update_game_pipeline(
    sophon_tools: any,
    options: {
        edition: GameEdition;
        from_version: string;
        threads: number?;
        target_memory_usage: number?;
        fast_verify: boolean?,
        user_agent: string?;
        proxy: string?;
    }
)
    local future = nil

    local progress = {
        fetch_info = false,
        updater_verify = { current = 0, total = 0, finished = false },
        updater_download = { current = 0, total = 0, finished = false },
        updater_patch = { current = 0, total = 0, finished = false },
        repairer_verify = { current = 0, total = 0, finished = false },
        repairer_download = { current = 0, total = 0, finished = false }
    }

    return {
        title = i18n("update_game_title"),
        pipeline = {
            {
                title = i18n("fetch_update_info_title"),

                perform = function()
                    local options = {
                        game_id = SOPHON_GAME_ID[options.edition],
                        game_dir = GAME_DIR[options.edition],

                        from_version = options.from_version,
                        threads = options.threads,
                        target_memory_usage = options.target_memory_usage,

                        verify_before_updating =
                            if options.fast_verify == true then "fast" else "full",

                        verify_before_patching =
                            if options.fast_verify == true then "fast" else "full",

                        api = {
                            region = options.edition
                        },

                        network = {
                            user_agent = options.user_agent,
                            proxy = options.proxy
                        }
                    }

                    future = sophon_tools.game.update(options, function(msg)
                        progress.fetch_info = true

                        if msg.type == "updater-verify" then
                            progress.updater_verify.current = msg.current
                            progress.updater_verify.total = msg.total
                        elseif msg.type == "updater-download" then
                            progress.updater_verify.finished = true

                            progress.updater_download.current = msg.current
                            progress.updater_download.total = msg.total
                        elseif msg.type == "updater-patch" then
                            progress.updater_verify.finished = true
                            progress.updater_download.finished = true

                            progress.updater_patch.current = msg.current
                            progress.updater_patch.total = msg.total
                        elseif msg.type == "repairer-verify" then
                            progress.updater_verify.finished = true
                            progress.updater_download.finished = true
                            progress.updater_patch.finished = true

                            progress.repairer_verify.current = msg.current
                            progress.repairer_verify.total = msg.total
                        elseif msg.type == "repairer-download" then
                            progress.updater_verify.finished = true
                            progress.updater_download.finished = true
                            progress.updater_patch.finished = true
                            progress.repairer_verify.finished = true

                            progress.repairer_download.current = msg.current
                            progress.repairer_download.total = msg.total

                            if msg.current == msg.total then
                                progress.repairer_download.finished = true
                            end
                        end
                    end)

                    while not progress.fetch_info and future do
                        local status, _ = future:poll()

                        if status then
                            future = nil

                            progress.fetch_info = true
                            progress.updater_verify.finished = true
                            progress.updater_download.finished = true
                            progress.updater_patch.finished = true
                            progress.repairer_verify.finished = true
                            progress.repairer_download.finished = true
                        end
                    end
                end
            },
            {
                title = i18n("verify_available_files_title"),

                before = function()
                    return not progress.updater_verify.finished and future
                end,

                perform = function(updater: any)
                    while not progress.updater_verify.finished and future do
                        local status, _ = future:poll()

                        updater({
                            current = progress.updater_verify.current,
                            total = progress.updater_verify.total,
                            format = function()
                                return i18n("verifying_progress_gb", {
                                    current = string.format("%.2f", progress.updater_verify.current / 1024 / 1024 / 1024),
                                    total = string.format("%.2f", progress.updater_verify.total / 1024 / 1024 / 1024)
                                })
                            end
                        })

                        if status then
                            future = nil

                            progress.fetch_info = true
                            progress.updater_verify.finished = true
                            progress.updater_download.finished = true
                            progress.updater_patch.finished = true
                            progress.repairer_verify.finished = true
                            progress.repairer_download.finished = true
                        end
                    end
                end
            },
            {
                title = i18n("download_files_patches_title"),

                before = function()
                    return not progress.updater_download.finished and future
                end,

                perform = function(updater: any)
                    while not progress.updater_download.finished and future do
                        local status, _ = future:poll()

                        updater({
                            current = progress.updater_download.current,
                            total = progress.updater_download.total,
                            format = function()
                                return i18n("downloading_progress_gb", {
                                    current = string.format("%.2f", progress.updater_download.current / 1024 / 1024 / 1024),
                                    total = string.format("%.2f", progress.updater_download.total / 1024 / 1024 / 1024)
                                })
                            end
                        })

                        if status then
                            future = nil

                            progress.fetch_info = true
                            progress.updater_verify.finished = true
                            progress.updater_download.finished = true
                            progress.updater_patch.finished = true
                            progress.repairer_verify.finished = true
                            progress.repairer_download.finished = true
                        end
                    end
                end
            },
            {
                title = i18n("patch_update_files_title"),

                before = function()
                    return not progress.updater_patch.finished and future
                end,

                perform = function(updater: any)
                    while not progress.updater_patch.finished and future do
                        local status, _ = future:poll()

                        updater({
                            current = progress.updater_patch.current,
                            total = progress.updater_patch.total,
                            format = function()
                                return i18n("processing_progress_gb", {
                                    current = string.format("%.2f", progress.updater_patch.current / 1024 / 1024 / 1024),
                                    total = string.format("%.2f", progress.updater_patch.total / 1024 / 1024 / 1024)
                                })
                            end
                        })

                        if status then
                            future = nil

                            progress.fetch_info = true
                            progress.updater_verify.finished = true
                            progress.updater_download.finished = true
                            progress.updater_patch.finished = true
                            progress.repairer_verify.finished = true
                            progress.repairer_download.finished = true
                        end
                    end
                end
            },
            {
                title = i18n("verify_updated_files_title"),

                before = function()
                    return not progress.repairer_verify.finished and future
                end,

                perform = function(updater: any)
                    while not progress.repairer_verify.finished and future do
                        local status, _ = future:poll()

                        updater({
                            current = progress.repairer_verify.current,
                            total = progress.repairer_verify.total,
                            format = function()
                                return i18n("verifying_progress_gb", {
                                    current = string.format("%.2f", progress.repairer_verify.current / 1024 / 1024 / 1024),
                                    total = string.format("%.2f", progress.repairer_verify.total / 1024 / 1024 / 1024)
                                })
                            end
                        })

                        if status then
                            future = nil

                            progress.fetch_info = true
                            progress.repairer_verify.finished = true
                            progress.updater_download.finished = true
                            progress.updater_patch.finished = true
                            progress.repairer_verify.finished = true
                            progress.repairer_download.finished = true
                        end
                    end
                end
            },
            {
                title = i18n("repair_files_title"),

                before = function()
                    return not progress.repairer_download.finished and future
                end,

                perform = function(updater: any)
                    while not progress.repairer_download.finished and future do
                        local status, _ = future:poll()

                        updater({
                            current = progress.repairer_download.current,
                            total = progress.repairer_download.total,
                            format = function()
                                return i18n("downloading_progress_gb", {
                                    current = string.format("%.2f", progress.repairer_download.current / 1024 / 1024 / 1024),
                                    total = string.format("%.2f", progress.repairer_download.total / 1024 / 1024 / 1024)
                                })
                            end
                        })

                        if status then
                            future = nil

                            progress.fetch_info = true
                            progress.updater_verify.finished = true
                            progress.updater_download.finished = true
                            progress.updater_patch.finished = true
                            progress.repairer_verify.finished = true
                            progress.repairer_download.finished = true
                        end
                    end
                end
            },
            {
                title = i18n("finalize_download_title"),

                perform = function()
                    if future then
                        future:await()
                    end

                    local game_info = sophon_tools.game.detect({
                        game_dir = GAME_DIR[options.edition],
                        network = {
                            user_agent = options.user_agent,
                            proxy = options.proxy
                        }
                    }):await()

                    if game_info and game_info.version then
                        game_version_write(options.edition, game_info.version)
                    end
                end
            }
        }
    }
end

----------------------------- integration -----------------------------

return function()
    local iter = import("iterable")

    local settings = get_settings_layout()

    local sophon_tools = import("sophon-tools")()

    local lua_proton = import("lua-proton").proton({
        umu_launcher = {
            game_id = "umu-zenlesszonezero"
        },

        prefix = {
            name = "zenless_zone_zero"
        },

        components = {
            get_enabled = function() return true end,
            set_enabled = function() end,

            uninstall = function(
                variant: GameVariant,
                component: string,
                updater: any
            )
                if component == "sophon_tools_cache" then
                    sophon_tools.cache.clear():await()
                end
            end
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
                        name = "china",
                        title = i18n("china_game_edition_title")
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

                -- If sophon-tools is not installed then we cannot fetch info
                -- about the game, so can't verify its version.
                if not sophon_tools.tool.verify() then
                    return nil
                end

                -- Check if lua-proton is ready to launch the game.
                if not lua_proton.game.can_launch() then
                    return nil
                end

                -- Fetch list of available game versions.
                local user_agent = settings.get_property("sophon_tools.user_agent")
                local proxy = settings.get_property("sophon_tools.proxy")

                local game_versions = sophon_tools.api.versions({
                    game_id = SOPHON_GAME_ID[variant.edition],
                    api = {
                        region = variant.edition
                    },
                    network = {
                        user_agent = user_agent,
                        proxy = proxy
                    }
                }):await()

                -- Check if installed game version is not latest.
                if game_version ~= game_versions[1].version then
                    return nil
                end

                -- Try to obtain game launch info from the lua-proton library.
                -- It will return nil if selected proton is not available.
                local launch_info = lua_proton.game.wrap_launch_info({
                    binary = GAME_BINARY[variant.edition],
                    env = {
                        WINE_ENABLE_TIMEOUT_FIX = if settings.get_property("game.timeout_fix") == true then "1" else "0"
                    }
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

                -- Update sophon-tools.
                if not sophon_tools.tool.verify() then
                    return get_update_sophon_tools_pipeline(sophon_tools)
                end

                -- Update game files.
                variant.edition = variant.edition or "global" :: GameEdition

                local user_agent = settings.get_property("sophon_tools.user_agent")
                local proxy = settings.get_property("sophon_tools.proxy")
                local target_memory_usage = settings.get_property("sophon_tools.target_memory_usage")

                if target_memory_usage then
                    target_memory_usage *= 1024 * 1024
                end

                local game_version = game_version_read(variant.edition)

                -- Get pipeline to download game files if it's not available.
                if not game_version then
                    return get_download_game_pipeline(sophon_tools, {
                        edition = variant.edition,
                        threads = settings.get_property("sophon_tools.threads"),
                        target_memory_usage = target_memory_usage,
                        fast_verify = settings.get_property("sophon_tools.fast_verify"),
                        user_agent = user_agent,
                        proxy = proxy
                    })
                end

                -- Fetch list of available game versions.
                local game_versions = sophon_tools.api.versions({
                    game_id = SOPHON_GAME_ID[variant.edition],
                    api = {
                        region = variant.edition
                    },
                    network = {
                        user_agent = user_agent,
                        proxy = proxy
                    }
                }):await()

                -- We can't update games yet.
                if game_version ~= game_versions[1].version then
                    return get_update_game_pipeline(sophon_tools, {
                        edition = variant.edition,
                        from_version = game_version,
                        threads = settings.get_property("sophon_tools.threads"),
                        target_memory_usage = target_memory_usage,
                        fast_verify = settings.get_property("sophon_tools.fast_verify"),
                        user_agent = user_agent,
                        proxy = proxy
                    })
                end

                return nil
            end
        },

        components = {
            get_layout = function(variant: GameVariant)
                local cache_size = sophon_tools.cache.get_size():await()

                local components = {
                    {
                        title = i18n("sophon_tools_components_title"),
                        entries = {
                            {
                                name = "sophon_tools_cache",
                                title = i18n("sophon_tools_cache_title"),
                                description = i18n("sophon_tools_cache_description"),
                                values = {
                                    {
                                        title = i18n("sophon_tools_cache_size_title"),
                                        value =
                                            if cache_size > 1024 * 1024 * 1024 then `{string.format("%.2f", cache_size / 1024 / 1024 / 1024)} GB`
                                            elseif cache_size > 1024 * 1024 then `{string.format("%.2f", cache_size / 1024 / 1024)} MB`
                                            elseif cache_size > 1024 then `{string.format("%.2f", cache_size / 1024)} KB`
                                            else `{cache_size} B`
                                    }
                                }
                            }
                        }
                    }
                }

                return iter({})
                    .chain(components)
                    .chain(lua_proton.components.get_layout(variant))
                    .collect()
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
