-- components v0.1.2
-- Copyright (C) 2025 - 2026  Nikita Podvirnyi <krypt0nn@vk.com>
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

type Settings = {
    wine: {
        prefix: string,
        selected: string,
        groups: {
            -- https://github.com/Kron4ek/Wine-Builds
            wine_staging_tkg: boolean
        }
    },
    dxvk: {
        selected: string,
        groups: {
            -- https://github.com/doitsujin/dxvk
            dxvk: boolean,

            -- https://gitlab.com/Ph42oN/dxvk-gplasync
            dxvk_gplasync: boolean
        }
    }
}

type Options = {
    game: string,
    settings: {
        get_property: (name: string) -> any,
        set_property: (name: string, value: any) -> ()
    }
}

type GameVariant = {
    platform: string,
    edition: string
}

-- Not complete definition but enough for our job.
type GameLaunchInfo = {
    binary: string,
    args: { string }?,
    env: { [string]: string }?
}

local data_dir_path: string = path.persist_dir("components")

local wine_dir_path: string        = path.join(data_dir_path, "wine")
local wine_prefix_dir_path: string = path.join(data_dir_path, "prefix")
local dxvk_dir_path: string        = path.join(data_dir_path, "dxvk")

------------------------------------------------- Imports -------------------------------------------------

-- Since inputs of a package can't access other inputs of the same package here
-- we implicitly feed them with all the necessary info.

local __import_wine = nil
local __import_dxvk = nil

local function import_wine()
    if not __import_wine then
        __import_wine = {
            wine_staging_tkg = fs.read_file(import("wine-staging-tkg-src")):await()
        }
    end

    return import("wine")(clone(__import_wine))
end

local function import_dxvk()
    if not __import_dxvk then
        __import_dxvk = {
            dxvk = fs.read_file(import("dxvk-src")):await(),
            dxvk_gplasync = fs.read_file(import("dxvk-gplasync-src")):await()
        }
    end

    return import("dxvk")(clone(__import_dxvk))
end

------------------------------------------------- Module -------------------------------------------------

local downloader_handle: number = downloader.create()

return function(options: Options)
    local function get_settings(): Settings
        local iter = import("iterable")

        local wine = import_wine()
        local dxvk = import_dxvk()

        local function default_wine_version(): string
            return iter(iter(wine.versions.list()).first().versions).first().name
        end

        local function default_dxvk_version(): string
            return iter(iter(dxvk.versions.list()).first().versions).first().name
        end

        local function validate_wine_version(version: string?): string
            local valid = iter(wine.versions.list())
                .map(function(group) return group.versions end)
                .flatten()
                .any(function(entry) return entry.name == version end)

            if not valid then
                return default_wine_version()
            else
                return version
            end
        end

        local function validate_dxvk_version(version: string?): string
            local valid = iter(dxvk.versions.list())
                .map(function(group) return group.versions end)
                .flatten()
                .any(function(entry) return entry.name == version end)

            if not valid then
                return default_dxvk_version()
            else
                return version
            end
        end

        local function filter_wine_prefix_name(name: string?): string
            if name then
                name = name:gsub("^%s+", "")
            	name = name:gsub("%s+$", "")
            	name = name:gsub("[^%a%d]", "_")
            end

        	if not name or string.len(name) == 0 then
        	   name = "games"
        	end

        	return name or "games"
        end

        local function default(value: any, default: any): any
            if value == nil then
                return default
            else
                return value
            end
        end

        return {
            wine = {
                prefix = filter_wine_prefix_name(options.settings.get_property("wine.prefix")),
                selected = validate_wine_version(options.settings.get_property("wine.selected")),
                groups = {
                    wine_staging_tkg = default(options.settings.get_property("wine.groups.wine_staging_tkg"), true)
                }
            },
            dxvk = {
                selected = validate_dxvk_version(options.settings.get_property("dxvk.selected")),
                groups = {
                    dxvk = default(options.settings.get_property("dxvk.groups.dxvk"), true),
                    dxvk_gplasync = default(options.settings.get_property("dxvk.groups.dxvk_gplasync"), true)
                }
            }
        }
    end

    local function get_arch_from_platform(platform: string): "x64" | nil
        if string.gmatch(platform, "x86_64-.+") then
            return "x64"
        end

        return nil
    end

    -- Return pipeline of actions needed to prepare game runner.
    local function get_runner_diff_pipeline(variant: GameVariant): any
        local curr_platform_arch = get_arch_from_platform(variant.platform) or error(`unsupported architecture: {variant.platform}`)

        local iter = import("iterable")
        local i18n = import("i18n").i18n()

        local wine = import_wine()
        local dxvk = import_dxvk()

        local settings = get_settings()

        local selected_wine = iter(wine.versions.list())
            .map(function(group) return group.versions end)
            .flatten()
            .find(function(version) return version.name == settings.wine.selected end)

        if not selected_wine then
            error("failed to find selected wine version")
        end

        local selected_dxvk = iter(dxvk.versions.list())
            .map(function(group) return group.versions end)
            .flatten()
            .find(function(version) return version.name == settings.dxvk.selected end)

        if not selected_dxvk then
            error("failed to find selected dxvk version")
        end

        local wine_data_path: string   = path.join(wine_dir_path, settings.wine.selected)
        local wine_prefix_path: string = path.join(wine_prefix_dir_path, settings.wine.prefix)

        local should_update_wine: boolean   = not fs.exists(path.join(wine_data_path, selected_wine.features.binary))
        local should_update_prefix: boolean = not wine.prefix.is_valid(wine_prefix_path) or wine.prefix.get_wine_name(wine_prefix_path) ~= settings.wine.selected
        local should_update_dxvk: { name: string, arch: string } = dxvk.prefix.get_info(wine_prefix_path) or { name = "", arch = "" }

        local should_update_dxvk: boolean = should_update_dxvk.name ~= settings.dxvk.selected or should_update_dxvk.arch ~= curr_platform_arch

        if not should_update_wine and not should_update_prefix and not should_update_dxvk then
            return nil
        end

        local wine_download_output: string = path.join(path.temp_dir(), selected_wine.file)
        local dxvk_download_output: string = path.join(path.temp_dir(), selected_dxvk.file)

        return {
            title = i18n("update_game_runner_title"),

            pipeline = {
                {
                    title = i18n("download_wine_title"),

                    before = function() return should_update_wine end,

                    perform = function(updater)
                        local handle = downloader.download(downloader_handle, {
                            url = selected_wine.url,
                            output_file = wine_download_output,
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

                        downloader.wait(handle)
                    end
                },

                {
                    title = i18n("extract_wine_title"),

                    before = function() return should_update_wine end,

                    perform = function(updater)
                        local handle = archive.open(wine_download_output)

                        -- wine_dir_path instead of wine_data_path because we expect
                        -- every wine build archive to contain a parent folder inside.
                        archive.extract(handle, wine_dir_path, function(current: number, total: number)
                            updater({
                                current = current,
                                total = total,

                                format = function()
                                    local current = current / 1000 / 1000
                                    local total = total / 1000 / 1000

                                    return i18n("extraction_progress_mb", {
                                        current = math.floor(current * 100) / 100,
                                        total = math.floor(total * 100) / 100
                                    })
                                end
                            })
                        end)

                        archive.close(handle)

                        fs.remove(wine_download_output)
                    end
                },

                {
                    title = i18n("create_wine_prefix_title"),

                    before = function() return should_update_prefix end,

                    perform = function(updater)
                        fs.create_dir(wine_prefix_path):await()

                        wine.prefix.update(settings.wine.selected, wine_prefix_path)
                    end
                },

                {
                    title = i18n("download_dxvk_title"),

                    before = function() return should_update_dxvk end,

                    perform = function(updater)
                        local handle = downloader.download(downloader_handle, {
                            url = selected_dxvk.url,
                            output_file = dxvk_download_output,
                            continue_download = true,

                            progress = function(current: number, total: number)
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

                        downloader.wait(handle)
                    end
                },

                {
                    title = i18n("extract_dxvk_title"),

                    before = function() return should_update_dxvk end,

                    perform = function(updater)
                        local handle = archive.open(dxvk_download_output)

                        -- dxvk_dir_path instead of dxvk_data_path because we expect
                        -- every dxvk build archive to contain a parent folder inside.
                        archive.extract(handle, dxvk_dir_path, function(current: number, total: number)
                            updater({
                                current = current,
                                total = total,

                                format = function()
                                    local current = current / 1000 / 1000
                                    local total = total / 1000 / 1000

                                    return i18n("extraction_progress_mb", {
                                        current = math.floor(current * 100) / 100,
                                        total = math.floor(total * 100) / 100
                                    })
                                end
                            })
                        end)

                        archive.close(handle)

                        fs.remove(dxvk_download_output):await()
                    end
                },

                {
                    title = i18n("apply_dxvk_title"),

                    before = function() return should_update_dxvk end,

                    perform = function(updater)
                        dxvk.install(settings.dxvk.selected, wine_prefix_path, curr_platform_arch)
                    end
                }
            }
        }
    end

    return {
        game = {
            get_actions_pipeline = function(variant: GameVariant)
                return get_runner_diff_pipeline(variant)
            end,

            -- This method will return the original table with modified properties,
            -- so no standard-related properties will be missing even though
            -- the data type is missing them.
            wrap_launch_info = function(launch_info: GameLaunchInfo): GameLaunchInfo
                local wine = import_wine()
                local dxvk = import_dxvk()

                local settings = get_settings()

                local wine_prefix_path: string = path.join(wine_prefix_dir_path, settings.wine.prefix)

                launch_info = wine.wrap_launch_command(settings.wine.selected, wine_prefix_path, launch_info)
                launch_info = dxvk.wrap_launch_command(settings.dxvk.selected, launch_info)

                return launch_info
            end
        },

        settings = {
            get_property = options.settings.get_property,
            set_property = options.settings.set_property,

            get_layout = function(): any
                local iter = import("iterable")
                local i18n = import("i18n").i18n()

                local wine = import_wine()
                local dxvk = import_dxvk()

                local settings = get_settings()

                return {
                    {
                        title = i18n("game_runner_title"),

                        entries = {
                            {
                                name = "wine.prefix",

                                title = i18n("wine_prefix_name_title"),
                                description = i18n("wine_prefix_name_description"),

                                entry = {
                                    format = "text",
                                    value = settings.wine.prefix
                                }
                            },

                            {
                                name = "wine.selected",
                                title = i18n("wine_version_title"),

                                entry = {
                                    format = "enum",

                                    values = iter(wine.versions.list())
                                        .map(function(group)
                                            return iter(group.versions)
                                                .map(function(version)
                                                    return {
                                                        group = group.name,
                                                        version = version
                                                    }
                                                end)
                                                .collect()
                                        end)
                                        .flatten()
                                        .filter(function(version)
                                            return settings.wine.groups[version.group] or version.version.name == settings.wine.selected
                                        end)
                                        .fold({}, function(values, version)
                                            values[version.version.name] = version.version.title

                                            return values
                                        end),

                                    selected = settings.wine.selected
                                }
                            },

                            {
                                name = "dxvk.selected",
                                title = i18n("dxvk_version_title"),

                                entry = {
                                    format = "enum",

                                    values = iter(dxvk.versions.list())
                                        .map(function(group)
                                            return iter(group.versions)
                                                .map(function(version)
                                                    return {
                                                        group = group.name,
                                                        version = version
                                                    }
                                                end)
                                                .collect()
                                        end)
                                        .flatten()
                                        .filter(function(version)
                                            return settings.dxvk.groups[version.group] or version.version.name == settings.dxvk.selected
                                        end)
                                        .fold({}, function(values, version)
                                            values[version.version.name] = version.version.title

                                            return values
                                        end),

                                    selected = settings.dxvk.selected
                                }
                            },

                            {
                                title = i18n("available_wine_editions_title"),

                                entry = {
                                    format = "expandable",

                                    entries = iter(wine.versions.list())
                                        .map(function(group)
                                            return {
                                                name = `wine.groups.{group.name}`,
                                                title = group.title,

                                                reactivity = "release",

                                                entry = {
                                                    format = "switch",
                                                    value = settings.wine.groups[group.name]
                                                }
                                            }
                                        end)
                                        .collect()
                                }
                            },

                            {
                                title = i18n("available_dxvk_editions_title"),

                                entry = {
                                    format = "expandable",

                                    entries = iter(dxvk.versions.list())
                                        .map(function(group)
                                            return {
                                                name = `dxvk.groups.{group.name}`,
                                                title = group.title,

                                                reactivity = "release",

                                                entry = {
                                                    format = "switch",
                                                    value = settings.dxvk.groups[group.name]
                                                }
                                            }
                                        end)
                                        .collect()
                                }
                            }
                        }
                    }
                }
            end
        }
    }
end
