-- wuthering_waves integration v0.0.0
-- Copyright (C) 2025  Dylan Donnell <greenicedtea@tutanota.com>
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

type Variant = {
    platform: string,
    edition: string
}

type Version = {
    version: string,
    title: string,
    url: string
}

local i18n = import("i18n").i18n
local iter = import("iterable")
local jadeite = import("jadeite")
local dpatchz = import("dpatchz")

local data_dir_path: string = path.persist_dir("wuthering_waves")
local engine_configs_path = path.join(data_dir_path, "engine_configs")

-- game index URL
local function game_index(edition: string)
    if edition == "china" then
        return "https://prod-alicdn-gamestarter.kurogame.com/launcher/game/G153/50009_ZXniDENS4vnMhNEhl7cLOQMojTLKLGgu/index.json"
    end
    return "https://prod-alicdn-gamestarter.kurogame.com/launcher/game/G153/50004_obOHXFrFanqsaIEOmuKroCcbZkQRBC7c/index.json"
end

local function game_exe_path(edition: string)
    return path.join(data_dir_path, edition, "Client", "Binaries", "Win64", "Client-Win64-Shipping.exe")
end

-- read version from version file of given edition
local function get_installed_version(edition: string): string?
    local version_file_path: string = path.join(data_dir_path, edition, "version")

    if not fs.exists(version_file_path) then
        return nil
    end

    return str.from_bytes(fs.read_file(version_file_path)):gsub("%s", "")
end

-- write version to version file of given edition
local function set_installed_version(edition: string, version: string)
    local version_file_path: string = path.join(data_dir_path, edition, "version")
    fs.create_dir(data_dir_path)
    fs.write_file(version_file_path, str.to_bytes(version))
end

-- get resource information from index
local function get_resource_info(edition: string)
    local resp = net.fetch(game_index(edition))

    if resp.is_ok then
        -- parse index.json from response
        local body = str.decode(str.from_bytes(resp.body), "json")

        local current_version = body.default.config.version
        if not current_version then
            error(`current version not found`)
        end

        local cdn_url = nil
        if #body.default.cdnList > 0 then
            cdn_url = body.default.cdnList[1].url
        else
            error(`cdn url not found`)
        end

        -- get resources URL
        local index_file = nil
        if body.default.config.indexFile then
            index_file = cdn_url .. body.default.config.indexFile
        else
            error(`resources url not found`)
        end

        -- get resources base path
        local base_url = nil
        if body.default.config.baseUrl then
            base_url = cdn_url .. body.default.config.baseUrl
        else
            error(`resources base path not found`)
        end

        -- get patchConfig
        local patch_config = nil
        if body.default.config.patchConfig then
            patch_config = body.default.config.patchConfig
        else
            error(`patchConfig not found`)
        end

        return {
            cdn_url = cdn_url,
            version = current_version,
            index_file = index_file,
            base_url = base_url,
            patch_config = patch_config
        }
    end

    return nil
end

-- assume game is installed if game exe path and version file exists
local function is_game_installed(edition: string): boolean
    local installed_version = get_installed_version(edition)

    if not installed_version then
        return false
    end

    return fs.exists(game_exe_path(edition))
end


local function parallel_download(files, base_url, output_dir, max_parallel, progress_callback)
    -- calculate total download size
    local total_size = iter(files).cloned().fold(0, function(acc, f)
        return acc + f.size
    end)

    -- store downloaded bytes of each file in table
    local download_progress = {}
    for i = 1, #files do
        download_progress[i] = 0
    end

    -- create shared downloader
    local downloader_handle = downloader.create()
    local active_tasks = {}
    local file_index = 1
    local completed_count = 0

    -- start a download for a file
    local function start_download(idx)
        local file = files[idx]
        local dest_path = path.join(output_dir, file.dest)

        -- skip file if exists
        if fs.exists(dest_path) then
            download_progress[idx] = file.size
            progress_callback(iter(download_progress).cloned().sum(), total_size)
            completed_count += 1
            return false
        end

        -- calculate file URL
        local file_url = base_url .. string.gsub(file.dest, " ", "%%20")

        -- download the file, callback with sum of downloaded file sizes
        local task_handle = downloader.download(downloader_handle, {
            url = file_url,
            output_file = dest_path,
            continue_download = true,

            on_update = function(current, _)
                download_progress[idx] = current
                progress_callback(iter(download_progress).cloned().sum(), total_size)
            end,

            on_finish = function(total)
                download_progress[idx] = total
                progress_callback(iter(download_progress).cloned().sum(), total_size)
                print(`finished downloading "{file.dest}"`)
            end
        })

        active_tasks[idx] = task_handle
        return true
    end

    -- start initial batch of downloads
    while file_index <= #files and #active_tasks < max_parallel do
        start_download(file_index)
        file_index += 1
    end

    -- maintain max_parallel active downloads
    while completed_count < #files do
        -- check for completed downloads
        local completed_files = {}
        for idx, task_handle in pairs(active_tasks) do
            local progress = downloader.progress(task_handle)
            if progress.finished then
                table.insert(completed_files, idx)
                completed_count += 1
            end
        end

        -- remove completed downloads from active_tasks
        for _, idx in ipairs(completed_files) do
            downloader.wait(active_tasks[idx])
            active_tasks[idx] = nil
        end

        -- start new downloads to fill up to max_parallel
        while file_index <= #files and #active_tasks < max_parallel do
            start_download(file_index)
            file_index += 1
        end

        -- should probably sleep here but there is not a sane way to do it in lua
    end

    downloader.close(downloader_handle)
end


-- find patch config corresponding to from_version
local function get_patch_config(resource_info, from_version: string)
    for i, config in resource_info.patch_config do
        if config.version == from_version then
            return config
        end
    end

    return nil
end

-- get configs from https://github.com/AlteriaX/WuWa-Configs, return version installed
local function get_engine_config()
    local latest_version_file = path.join(engine_configs_path, ".latest")

    -- fetch tags
    local tags_resp = net.fetch("https://api.github.com/repos/AlteriaX/WuWa-Configs/tags", {
        method = "get",
        headers = {
            ["User-Agent"] = "curl/8.13.0",
            ["Accept"] = "*/*"
        },
        body = {}
    })
    if tags_resp.is_ok then
        -- decode json
        local tags_json = str.decode(str.from_bytes(tags_resp.body), "json")
        local latest = tags_json[1]
        local name = latest["name"]

        -- if target path exists, no need to redownload
        if fs.exists(path.join(engine_configs_path, "WuWa-Configs-" .. name:gsub("v", ""))) then
            return name
        end

        local output_file = path.join(path.temp_dir(), `engine_configs_{name}.zip`)

        -- download archive
        local handle = downloader.create()
        local task = downloader.download(handle, {
            url = `https://github.com/AlteriaX/WuWa-Configs/archive/refs/tags/{name}.zip`,
            output_file = output_file
        })
        downloader.wait(task)
        downloader.close(handle)

        -- extract archive
        local arch = archive.open(output_file, "zip")
        archive.extract(arch, engine_configs_path)
        archive.close(arch)

        -- remove archive
        fs.remove(output_file)

        -- write latest version file
        fs.write_file(latest_version_file, name)

        return name
    else
        -- github isn't accessible, return the last downloaded version
        if fs.exists(latest_version_file) then
            return fs.read_file(latest_version_file)
        end
    end

    error(`no response from github api`)
    return ""
end

-- overwite the Engine.ini file with the specified config number of a given version
local function apply_engine_config(edition, version, num)
    local engine_ini_src_path = path.join(engine_configs_path, "WuWa-Configs-" .. version:gsub("v", ""), "Config " .. num, "Engine.ini")
    local engine_ini_dest_path = path.join(data_dir_path, edition, "Client", "Saved", "Config", "WindowsNoEditor", "Engine.ini")

    if fs.exists(engine_ini_src_path) then
        fs.remove(engine_ini_dest_path)
    end

    if not fs.exists(engine_ini_dest_path) then
        fs.create_dir(path.join(data_dir_path, edition, "Client", "Saved", "Config", "WindowsNoEditor"))
    end

    fs.copy(engine_ini_src_path, engine_ini_dest_path)
end

-- test each file against its hash, return a list of non-matching hashes
local function test_hash(files, base_dir, progress_callback)
    local results = {}
    local total_size = iter(files).cloned().fold(0, function(acc, f)
        return acc + f.size
    end)
    local current_size = 0

    for _, file in ipairs(files) do
        local dest_path = path.join(base_dir, file.dest)

        -- remove existing file if it doesn't match the hash
        if fs.exists(dest_path) then
            print(`hashing file "{dest_path}"`)
            local file_hash = str.encode(hash.file(dest_path, "md5"), "hex")

            current_size += file.size
            progress_callback(current_size, total_size)

            -- remove file if non-matching
            if file_hash ~= file.md5 then
                table.insert(results, file)
            end
        else
            -- file missing
            table.insert(results, file)
        end
    end

    return results
end

-- redownload files until they pass the hash check
local function repair_files(files, base_url, output_dir, concurrent_downloads, updater)
    local hash_result = files
    while true do
        -- get hash result
        hash_result = test_hash(hash_result, output_dir, function(current_size, total_size)
            updater({
                title = i18n("hash"),
                progress = {
                    current = current_size,
                    total = total_size,
                    format = function()
                        local current_gb = math.floor((current_size / 1000 / 1000 / 1000) * 10) / 10
                        local total_gb = math.floor((total_size / 1000 / 1000 / 1000) * 10) / 10

                        return i18n("processing_progress", {
                            current = current_gb,
                            total = total_gb
                        })
                    end
                }
            })
        end)

        -- no corrupted files
        if #hash_result == 0 then
            return
        end

        -- remove corrupted files
        for _, file in hash_result do
            fs.remove(path.join(output_dir, file.dest))
        end

        -- redownload corrupted files
        parallel_download(
            hash_result,
            base_url,
            output_dir,
            concurrent_downloads,
            function(current, total)
                updater({
                    title = i18n("repair_game_files"),
                    progress = {
                        current = current,
                        total = total,
                        format = function()
                            -- convert to gb for display
                            local current_gb = math.floor((current / 1000 / 1000 / 1000) * 10) / 10
                            local total_gb = math.floor((total / 1000 / 1000 / 1000) * 10) / 10

                            return i18n("repairing_progress", {
                                current = current_gb,
                                total = total_gb
                            })
                        end
                    }
                })
            end
        )
    end
end

-- settings management
local __settings = nil
local __components = nil

local function import_settings()
    if not __settings then
        __settings = import("settings")({
            game = "wuthering_waves",
            layout = {
                game = {
                    title = i18n("game"),
                    entries = {
                        dx11 = {
                            title = "Use DX11",
                            description = "Run game with DirectX 11 instead of DirectX 12",
                            entry = {
                                format = "switch",
                                default = true
                            }
                        },
                        skip_splash = {
                            title = "Skip splash",
                            description = "Skip intro videos",
                            entry = {
                                format = "switch",
                                default = false
                            }
                        },
                        engine_config = {
                            title = "Alternate engine config",
                            description = "Replace Engine.ini with config from AlteriaX/WuWa-Configs",
                            entry = {
                                format = "enum",
                                default = "none",
                                values = {
                                    none = "None",
                                    c1 = "Config 1",
                                    c2 = "Config 2",
                                    c3 = "Config 3",
                                    c4 = "Config 4",
                                    c5 = "Config 5"
                                }
                            }
                        },
                        wayland = {
                            title = "Use wine wayland",
                            description = "Unset DISPLAY so wine wayland is used by default",
                            entry = {
                                format = "switch",
                                default = false
                            }
                        }
                    }
                },
                download = {
                    title = i18n("download"),
                    entries = {
                        max_parallel = {
                            title = "Max parallel downloads",
                            description = "Maximum number of downloads to run in parallel",
                            entry = {
                                format = "text",
                                default = "8"
                            }
                        }
                    }
                }
            }
        })
    end

    return __settings
end

local function import_components()
    if not __components then
        local settings = import_settings()

        __components = import("components").components({
            game = "wuthering_waves",
            settings = {
                get_property = settings.get_property,
                set_property = settings.set_property
            }
        })
    end

    return __components
end

return {
    standard = 1,

    editions = function(platform: string)
        return {
            { name = "global", title = i18n("global_game_edition") },
            { name = "china",  title = i18n("china_game_edition")  }
        }
    end,

    game = {
        get_status = function(variant: Variant)
            local components = import_components()
            local status = components.game.get_status(variant)

            if status then
                return status
            end

            if not is_game_installed(variant.edition) then
                return "not-installed"
            end

            -- check if there's a newer version available
            local resource_info = get_resource_info(variant.edition)
            local installed_version = get_installed_version(variant.edition)

            if installed_version and resource_info.version and installed_version ~= resource_info.version then
                return "update-required"
            end

            return "installed"
        end,

        get_diff = function(variant: Variant)
            local components = import_components()
            local diff = components.game.get_diff(variant)

            -- components diff
            if diff then
                return diff
            end

            local resource_info = get_resource_info(variant.edition)
            local installed_version = get_installed_version(variant.edition)
            local output_dir = path.join(data_dir_path, variant.edition)

            -- get max parallel setting
            local settings = import_settings()
            local concurrent_downloads = tonumber(settings.get_property("download.max_parallel"))

            -- get indexFile.json
            local index_file_resp = net.fetch(resource_info.index_file)
            if not index_file_resp.is_ok then
                error(`could not fetch indexFile.json`)
                return
            end
            local index_file_data = str.decode(str.from_bytes(index_file_resp.body), "json")

            -- update
            if is_game_installed(variant.edition) then
                -- check if version is not latest
                if installed_version and resource_info.version and installed_version ~= resource_info.version then
                    -- get patch config for installed version to latest version
                    local patch_config = get_patch_config(resource_info, installed_version)
                    if patch_config then
                        -- get indexFile.json
                        local update_index_file_resp = net.fetch(resource_info.cdn_url .. patch_config.indexFile)
                        if not update_index_file_resp.is_ok then
                            error(`could not fetch indexFile.json`)
                            return
                        end
                        local update_index_file = str.decode(str.from_bytes(update_index_file_resp.body), "json")

                        -- find file that ends with .krdiff
                        local diff_file = iter(update_index_file.resource).cloned().find(function(f)
                            return f.dest:sub(-7) == ".krdiff"
                        end)
                        local diff_file_dest = output_dir .. diff_file.dest

                        return {
                            title = i18n("update_game"),
                            description = i18n("update_game_description", {
                                current = installed_version,
                                new = resource_info.version
                            }),
                            pipeline = {
                                {
                                    title = i18n("update"),
                                    perform = function(updater)
                                        -- download and patch the diff file
                                        local function progress(current, total)
                                            local current_gb = math.floor((current / 1000 / 1000 / 1000) * 10) / 10
                                            local total_gb = math.floor((total / 1000 / 1000 / 1000) * 10) / 10

                                            updater({
                                                title = i18n("update_game"),
                                                progress = {
                                                    current = current,
                                                    total = total,
                                                    format = i18n("downloading_progress", {
                                                        current = current_gb,
                                                        total = total_gb
                                                    })
                                                }
                                            })
                                        end

                                        -- download
                                        local downloader_handle = downloader.create()
                                        local task_handle = downloader.download(downloader_handle, {
                                            url = resource_info.cdn_url .. patch_config.baseUrl .. string.gsub(diff_file.dest, " ", "%%20"),
                                            output_file = diff_file_dest,
                                            continue_download = true,

                                            on_update = progress,

                                            on_finish = function(total)
                                                print(`finished downloading "{diff_file.dest}"`)
                                                progress(total, total)
                                            end
                                        })
                                        downloader.wait(task_handle)
                                        downloader.close(downloader_handle)

                                        -- patch
                                        dpatchz.patch_file(diff_file_dest, output_dir)
                                        print(`finished patching "{diff_file.dest}"`)

                                        fs.remove(diff_file_dest)
                                    end
                                },
                                {
                                    title = i18n("delete"),
                                    perform = function(updater)
                                        -- delete each path in the deleteFiles array
                                        for i, file in update_index_file.deleteFiles do
                                            fs.remove(path.join(output_dir, file))
                                        end
                                    end
                                },
                                {
                                    title = i18n("repair"),
                                    perform = function(updater)
                                        -- run repairer
                                        repair_files(
                                            index_file_data.resource,
                                            resource_info.base_url,
                                            output_dir,
                                            concurrent_downloads,
                                            updater
                                        )

                                        -- save version
                                        set_installed_version(variant.edition, resource_info.version)
                                    end
                                }
                            }
                        }
                    end

                    -- no patch, delete outdated files
                    print("no patch available")
                    fs.remove(output_dir)
                else
                    -- game is installed and up to date
                    return nil
                end
            end

            -- fresh installation
            return {
                title = i18n("install_game"),
                description = i18n("install_game_description", {
                    version = resource_info.version
                }),

                pipeline = {
                    {
                        title = i18n("download_game_files"),
                        perform = function(updater)
                            -- download game files
                            parallel_download(
                                index_file_data.resource,
                                resource_info.base_url,
                                output_dir,
                                concurrent_downloads,
                                function(current, total)
                                    updater({
                                        title = i18n("downloading_game_files"),
                                        progress = {
                                            current = current,
                                            total = total,
                                            format = function()
                                                -- convert to GB for display
                                                local current_gb = math.floor((current / 1000 / 1000 / 1000) * 10) / 10
                                                local total_gb = math.floor((total / 1000 / 1000 / 1000) * 10) / 10

                                                return i18n("downloading_progress", {
                                                    current = current_gb,
                                                    total = total_gb
                                                })
                                            end
                                        }
                                    })
                                end
                            )
                        end
                    },
                    {
                        title = i18n("repair"),
                        perform = function(updater)
                            -- run repairer
                            repair_files(
                                index_file_data.resource,
                                resource_info.base_url,
                                output_dir,
                                concurrent_downloads,
                                updater
                            )

                            -- save version
                            set_installed_version(variant.edition, resource_info.version)
                        end
                    }
                }
            }
        end,

        get_launch_info = function(variant: Variant)
            if not is_game_installed(variant.edition) then
                return {
                    status = "disabled",
                    hint = i18n("game_not_installed"),
                    binary = ""
                }
            end

            local settings = import_settings()

            -- overwrite engine config if specified
            local use_engine_config = settings.get_property("game.engine_config")
            if use_engine_config ~= "none" then
                local engine_config = get_engine_config()
                apply_engine_config(variant.edition, engine_config, use_engine_config:gsub("c", ""))
            end

            -- add -dx11 or -dx12 arg if specified in settings
            local args = {}
            local use_dx11 = settings.get_property("game.dx11")

            if use_dx11 then
                table.insert(args, "-dx11")
            else
                table.insert(args, "-dx12")
            end

            -- add -SkipSplash if specified in settings
            local skip_splash = settings.get_property("game.skip_splash")

            if skip_splash then
                table.insert(args, "-SkipSplash")
            end

            -- add empty DISPLAY envvar if specified in settings
            -- first overrides are for dxvk, second is to disable popup window
            local env = { WINEDLLOVERRIDES = "d3d8,d3d9,d3d10core,d3d11,dxgi=n;KRSDKExternal.exe=d" }
            local use_wayland = settings.get_property("game.wayland")

            if use_wayland then
                env["DISPLAY"] = ""
            end

            -- run game
            local components = import_components()
            return components.game.wrap_launch_info(jadeite.wrap_launch_command({
                status = "normal",
                binary = game_exe_path(variant.edition),
                args = args,
                env = env
            }))
        end
    },

    settings = {
        get_property = function(name: string)
            local settings = import_settings()
            return settings.get_property(name)
        end,

        set_property = function(name: string, value: any)
            local settings = import_settings()
            settings.set_property(name, value)
        end,

        get_layout = function(variant: Variant)
            local settings = import_settings()
            local components = import_components()

            return iter(settings.get_layout(variant))
                .chain(components.settings.get_layout())
                .collect()
        end
    }
}
