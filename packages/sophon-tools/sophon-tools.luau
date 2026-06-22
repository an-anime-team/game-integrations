-- sophon-tools v0.1.1
-- Copyright (C) 2026 Nikita Podvirnyi <krypt0nn@vk.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the “Software”), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

local DOWNLOAD_INFO = {
    url = "https://dawn.wine/dawn-winery/sophon-tools/releases/download/v0.1.7/sophon-cli",
    hash = "c5ac1678e5091aedecc9eee105eeb912a990f59acc21426788c1b459d81e0abe"
}

local DATA_DIR: string = path.persist_dir("sophon-tools")

local BINARY_PATH: string = path.join(DATA_DIR, "sophon-cli")
local CACHE_DIR: string = path.join(DATA_DIR, "cache")

type Promise<T> = any

type SophonRegion = "global" | "china"

-- Check if the sophon-tools binary is available and its hash is matching the
-- known one.
local function verify_binary(binary_path: string): boolean
    if not path.exists(binary_path) then
        return false
    end

    local binary_hash = hash.digitize_file("blake3", binary_path):await()

    return str.encode("hex", binary_hash) == DOWNLOAD_INFO.hash
end

local __list_games_cache = {}
local __game_info_cache = {}

return function(binary_path: string?)
    local binary_path: string = binary_path or BINARY_PATH

    if not path.permissions(binary_path).write then
        error("sophon-tools module doesn't have access to the binary path")
    end

    local function ensure_verified_binary()
        if not verify_binary(binary_path) then
            error("invalid sophon-tools binary hash")
        end
    end

    return {
        tool = {
            path = clone(binary_path),

            -- Download sophon-tools binary. Overwrite existing binary if it's
            -- available.
            download = function(updater: (current: number, total: number) -> ())
                local downloader_handle = downloader.create()

                local task_handle = downloader.download(downloader_handle, {
                    url = DOWNLOAD_INFO.url,
                    output_file = binary_path,
                    continue_download = false,
                    on_update = updater
                })

                downloader.wait(task_handle)
                downloader.close(downloader_handle)

                if not verify_binary(binary_path) then
                    fs.remove_file(binary_path):await()

                    error("downloaded sophon-tools binary has invalid hash")
                end

                -- Ensure that the downloaded binary is executable.
                process.exec("chmod", { "+x", binary_path }):await()
            end,

            -- Verify installed sophon-tools binary.
            verify = function(): boolean
                return verify_binary(binary_path)
            end
        },

        game = {
            -- List information about available games for the given edition.
            -- This is async function that returns a Promise<...> object.
            list_games = function(region: SophonRegion?): Promise<{{ id: string, versions: {string} }}>
                local region: SophonRegion = region or "global" :: SophonRegion

                local cache_key = `{DOWNLOAD_INFO.hash}-{region}`

                if __list_games_cache[cache_key] then
                    return task.create(function() return true, __list_games_cache[cache_key] end)
                end

                -- TODO: move this check inside of the promise
                ensure_verified_binary()

                local future = process.exec(binary_path, {
                    "--edition", region,
                    "--cache-dir", CACHE_DIR,
                    "dump", "--format", "json", "game-scan-info"
                })

                return task.create(function(): (boolean, any)
                    local status, result = future:poll()

                    if not status then
                        return false, nil
                    end

                    if not result.is_ok then
                        error("sophon-tools module failed to fetch information about available games")
                    end

                    if #result.stdout <= 2 then
                        return true, {}
                    end

                    local tool_response = str.decode("json", str.from_bytes(result.stdout))

                    if not tool_response.game_scan_info then
                        error("sophon-tools binary returned invalid information about available games")
                    end

                    local games_info = {}

                    for _, response in ipairs(tool_response.game_scan_info) do
                        if not response.game_id or not response.game_exe_list then
                            error("sophon-tools binary returned invalid information about available games")
                        end

                        local versions = {}

                        for _, version_info in ipairs(response.game_exe_list) do
                            if not version_info.version then
                                error("sophon-tools binary returned invalid information about available games")
                            end

                            table.insert(versions, version_info.version)
                        end

                        table.insert(games_info, {
                            id = response.game_id,
                            versions = versions
                        })
                    end

                    __list_games_cache[cache_key] = games_info

                    return true, games_info
                end)
            end,

            -- List available versions for the given game.
            -- This is async function that returns a Promise<...> object.
            get_info = function(game_id: string, region: SophonRegion?): Promise<{
                -- Latest game version.
                version: string,

                -- List of versions from which the game can be updated.
                updatable_versions: {string},

                -- List of game components.
                components: {{ id: string, name: string }}
            }?>
                local region: SophonRegion = region or "global" :: SophonRegion

                local cache_key = `{DOWNLOAD_INFO.hash}-{region}-{game_id}`

                if __game_info_cache[cache_key] then
                    return task.create(function() return true, __game_info_cache[cache_key] end)
                end

                -- TODO: move this check inside of the promise
                ensure_verified_binary()

                local future = process.exec(binary_path, {
                    "--edition", region,
                    "--cache-dir", CACHE_DIR,
                    "dump", "--format", "json", "package-info", game_id
                })

                return task.create(function(): (boolean, any)
                    local status, result = future:poll()

                    if not status then
                        return false, nil
                    end

                    if not result.is_ok then
                        error("sophon-tools module failed to fetch information about the game")
                    end

                    if #result.stdout <= 2 then
                        return true, nil
                    end

                    local tool_response = str.decode("json", str.from_bytes(result.stdout))

                    local components = {}

                    for _, component_info in ipairs(tool_response.categories) do
                        table.insert(components, {
                            id = component_info.category_id,
                            name = component_info.matching_field
                        })
                    end

                    local game_info = {
                        version = tool_response.tag,
                        updatable_versions = tool_response.diff_tags,
                        components = components
                    }

                    __game_info_cache[cache_key] = game_info

                    return true, game_info
                end)
            end,

            -- Download game files to the given directory.
            download = function(
                options: {
                    region: SophonRegion?,

                    game_id: string,
                    game_dir: string,

                    -- Name of the component to download.
                    -- Default is "game".
                    component: string?,

                    -- Check if there's enough space to download the game files.
                    -- Default is true.
                    check_available_space: boolean?,

                    -- Whether to store downloaded chunks in memory. If enabled,
                    -- files could be patched faster due to less required
                    -- disk reads.
                    --
                    -- Default is false.
                    use_memory_buffer: boolean?,

                    -- Maximal amount of bytes that can be stored in the memory.
                    -- Default is 256 MB.
                    memory_buffer_size: number?,

                    -- Amount of threads to use in downloader.
                    -- Default is 2.
                    threads_num: number?,

                    -- Callback called on chunks data downloading in bytes.
                    on_download: ((current: number, total: number) -> ())?,

                    -- Callback called on files patching. Represent current and
                    -- total amount of files patched.
                    on_patch: ((current: number, total: number) -> ())?
                }
            )
                if not options.game_dir or not path.permissions(options.game_dir).write then
                    error("sophon-tools module requires writable game directory path")
                end

                if not fs.exists(options.game_dir) then
                    fs.create_dir(options.game_dir):await()
                end

                local args = {
                    "--edition", options.region or "global" :: SophonRegion,
                    "--cache-dir", CACHE_DIR,
                    "--threads", tostring(options.threads_num or 2),
                    "download",
                    "--status-format", "ndjson"
                }

                if options.check_available_space == false then
                    table.insert(args, "--skip-free-space-check")
                end

                if options.use_memory_buffer then
                    table.insert(args, "--chunk-buffer-memory")
                    table.insert(args, "--memory-buffer-limit")

                    if options.memory_buffer_size then
                        table.insert(args, tostring(options.memory_buffer_size))
                    else
                        table.insert(args, tostring(256 * 1024 * 1024))
                    end
                end

                table.insert(args, options.game_id)
                table.insert(args, options.game_dir)

                ensure_verified_binary()

                local handle = process.open(binary_path, args)

                while not process.finished(handle) do
                    local output = process.stdout(handle)

                    if output and (options.on_download or options.on_patch) then
                        for line in str.from_bytes(output):gmatch("([^\n\r]+)") do
                            if line then
                                local status, message = pcall(str.decode, "json", line)

                                if status then
                                    if message.Download and message.Download.DownloadingProgressBytes and options.on_download then
                                        options.on_download(
                                            message.Download.DownloadingProgressBytes.downloaded_bytes,
                                            message.Download.DownloadingProgressBytes.total_bytes
                                        )
                                    end

                                    if message.Download and message.Download.DownloadingProgressFiles and options.on_patch then
                                        options.on_patch(
                                            message.Download.DownloadingProgressFiles.downloaded_files,
                                            message.Download.DownloadingProgressFiles.total_files
                                        )
                                    end
                                end
                            end
                        end
                    end
                end

                -- Wait so that process will definitely be closed and removed
                -- from the memory.
                process.wait(handle)
            end
        },

        cache = {
            -- Get size of the sophon-tools cache directory in bytes.
            -- This is async function that returns a Promise<number> object.
            get_size = function(): Promise<number>
                local function get_dir_size(dir_path: string)
                    local read_dir_result = { is_finished = false, value = fs.read_dir(dir_path) }
                    local read_nested_dirs = {}

                    local size = 0

                    return task.create(function(): (boolean, number?)
                        if not read_dir_result.is_finished then
                            local status, result = read_dir_result.value:poll()

                            if status then
                                read_dir_result.is_finished = true
                                read_dir_result.value = nil

                                for _, entry in ipairs(result) do
                                    if entry.type == "directory" then
                                        table.insert(read_nested_dirs, {
                                            is_finished = false,
                                            value = get_dir_size(entry.path)
                                        })
                                    else
                                        size += fs.metadata(entry.path).length
                                    end
                                end
                            end

                            return false, nil
                        else
                            local has_pending = false

                            for _, task in ipairs(read_nested_dirs) do
                                if not task.is_finished then
                                    has_pending = true

                                    local status, result = task.value:poll()

                                    if status then
                                        task.is_finished = true
                                        task.value = nil :: any

                                        size += result
                                    end
                                end
                            end

                            if not has_pending then
                                return true, size
                            else
                                return false, nil
                            end
                        end
                    end)
                end

                if not fs.exists(CACHE_DIR) then
                    return task.create(function() return true, 0 end)
                end

                return get_dir_size(CACHE_DIR)
            end,

            -- Clear the sophon-tools cache directory.
            -- This is async function that returns a Promise<nil> object.
            clear = function(): Promise<nil>
                if fs.exists(CACHE_DIR) then
                    return fs.remove_dir(CACHE_DIR)
                else
                    return task.create(function() return true, nil end)
                end
            end
        }
    }
end
