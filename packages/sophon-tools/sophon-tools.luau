-- sophon-tools lua bindings v0.2.2
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
--
-- Original tool: https://dawn.wine/dawn-winery/sophon-tools
-- licensed under GPL-3.0-or-later

local DOWNLOAD_INFO = {
    url = "https://dawn.wine/dawn-winery/sophon-tools/releases/download/v0.2.1/sophon-tools",
    hash = "cc15994967c434d04fd9a64b6c724f24a07d5441e5917a4b9b5f68a33f268ff5"
}

local DATA_DIR: string = path.persist_dir("sophon-tools")

local BINARY_PATH: string = path.join(DATA_DIR, "sophon-tools")
local CACHE_DIR: string = path.join(DATA_DIR, "cache")

type Promise<T> = any

----------------------------- sophon-tools responses -----------------------------

type GameInfo = {
    game: {
        id: string;
        biz: string;
    };
    version: string;
    diff_versions: {string};
    package: {
        id: string;
        branch: string;
        password: string;
    };
}

type GameComponentInfo = {
    id: string;
    name: string;
}

type GameVersionInfo = {
    version: string;
    hash_md5: string;
}

type GameDownloadFileInfo = {
    path: string;
    size: number;
    hash_md5: string;
    chunks: {{
        name: string;
        compressed: {
            size: number;
            hash_md5: string;
        };
        decompressed: {
            size: number;
            hash_md5: string;
        };
    }};
}

type DetectedGameInfo = {
    game: {
        id: string;
        biz: string;
    };
    binary: string;
    version: string;
}

type VerifyGameMsg =
    | {
        type: "available";
        result: "valid" | "invalid" | "unknown";
        current: number;
        total: number;
        path: string;
    }
    | {
        type: "missing";
        result: "missing";
        path: string;
    }

type DownloadGameMsg =
    | {
        type: "verify";
        result: "valid" | "invalid" | "unknown";
        current: number;
        total: number;
        path: string;
    }
    | {
        type: "download";
        current: number;
        total: number;
    }

type UpdateGameMsg =
    | {
        type: "updater-verify";
        result: "valid" | "invalid" | "unknown";
        current: number;
        total: number;
        path: string;
    }
    | {
        type: "updater-download";
        current: number;
        total: number;
    }
    | {
        type: "updater-patch";
        result: boolean;
        current: number;
        total: number;
        path: string;
    }
    | {
        type: "repairer-verify";
        result: "valid" | "invalid" | "unknown";
        current: number;
        total: number;
        path: string;
    }
    | {
        type: "repairer-download";
        current: number;
        total: number;
    }

----------------------------- api options -----------------------------

type SophonRegion = "global" | "china"

type ApiOptions = {
    region: SophonRegion?;
    launcher_id: string?;
}

type NetworkOptions = {
    user_agent: string?;
    proxy: string?;
    timeout: string | number | nil;
}

type ListGamesOptions = {
    api: ApiOptions?;
    network: NetworkOptions?;
}

type ListGameComponentsOptions = {
    game_id: string;
    show_all: boolean?;
    api: ApiOptions?;
    network: NetworkOptions?;
}

type ListGameVersionsOptions = {
    game_id: string;
    api: ApiOptions?;
    network: NetworkOptions?;
}

type ListGameFilesOptions = {
    game_id: string;
    component_id: string?;
    version: string?;
    regex: string?;
    api: ApiOptions?;
    network: NetworkOptions?;
}

-- Append API requests options to the sophon-tools CLI arguments.
local function append_api_options(
    options: ApiOptions?,
    args: {string}
): {string}
    if not options then
        return args
    end

    if options.region
        and typeof(options.region) == "string"
        and #options.region > 0
    then
        table.insert(args, "--region")
        table.insert(args, options.region)
    end

    if options.launcher_id
        and typeof(options.launcher_id) == "string"
        and #options.launcher_id > 0
    then
        table.insert(args, "--launcher-id")
        table.insert(args, options.launcher_id)
    end

    return args
end

-- Append API requests network options to the sophon-tools CLI arguments.
local function append_network_options(
    options: NetworkOptions?,
    args: {string}
): {string}
    if not options then
        return args
    end

    if options.user_agent
        and typeof(options.user_agent) == "string"
        and #options.user_agent > 0
    then
        table.insert(args, "--user-agent")
        table.insert(args, options.user_agent)
    end

    if options.proxy
        and typeof(options.proxy) == "string"
        and #options.proxy > 0
    then
        table.insert(args, "--proxy")
        table.insert(args, options.proxy)
    end

    if options.timeout
        and (
            (typeof(options.timeout) == "string" and #options.timeout > 0)
            or (typeof(options.timeout) == "number" and options.timeout > 0)
        )
    then
        table.insert(args, "--user-agent")
        table.insert(args, tostring(options.timeout))
    end

    return args
end

----------------------------- command options -----------------------------

type DetectGameOptions = {
    game_dir: string;
    network: NetworkOptions?;
}

type VerifyGameOptions = {
    game_id: string;
    game_dir: string;
    component_id: string?;
    version: string?;
    regex: string?;
    fast_verify: boolean?;
    show_missing: boolean?;
    threads: number?;
    api: ApiOptions?;
    network: NetworkOptions?;
}

type DownloadGameOptions = {
    game_id: string;
    game_dir: string;
    component_id: string?;
    version: string?;
    regex: string?;
    verify_manifest: "none" | "fast" | "full" | nil;
    verify_chunks: "none" | "fast" | "full" | nil;
    verify_before_downloading: "none" | "fast" | "full" | nil;
    threads: number?;
    target_memory_usage: string | number | nil;
    chunk_download_attempts: number?;
    fetch_manifest_timeout: number | string | nil;
    fetch_chunk_per_mb_timeout: number | string | nil;
    api: ApiOptions?;
    network: NetworkOptions?;
}

type UpdateGameOptions = {
    game_id: string;
    game_dir: string;
    chunks_dir: string?;
    component_id: string?;
    from_version: string?;
    to_version: string?;
    regex: string?;
    verify_manifest: "none" | "fast" | "full" | nil;
    verify_chunks: "none" | "fast" | "full" | nil;
    verify_before_updating: "none" | "fast" | "full" | nil;
    verify_before_patching: "none" | "fast" | "full" | nil;
    delete_unused_assets: boolean?;
    patch_assets: boolean?;
    delete_applied_chunks: boolean?;
    repair_broken_assets: "none" | "fast" | "full" | nil;
    threads: number?;
    target_memory_usage: string | number | nil;
    chunk_download_attempts: number?;
    fetch_manifest_timeout: number | string | nil;
    fetch_chunk_per_mb_timeout: number | string | nil;
    api: ApiOptions?;
    network: NetworkOptions?;
}

----------------------------- module -----------------------------

-- Check if the sophon-tools binary is available and its hash is matching the
-- known one.
local function verify_binary(binary_path: string): boolean
    if not path.exists(binary_path) then
        return false
    end

    local binary_hash = hash.digitize_file("blake3", binary_path):await()

    return str.encode("hex", binary_hash) == DOWNLOAD_INFO.hash
end

-- Read stdout from the given process handle, decode jsonl objects and pass them
-- to the given callback.
local function handle_process_jsonl_output(
    handle: any,
    callback: (any) -> ()
): Promise<boolean>
    local buf = ""
    local exit_status = nil

    return task.create(function(): (boolean, boolean?)
        if not handle then
            return true, exit_status
        end

        if process.finished(handle) then
            local output = process.wait(handle)

            if #output.stderr > 0 then
                error(`sophon-tools exited with error: {output.stderr:as_string()}`)
            end

            exit_status = output.is_ok
            handle = nil

            return true, exit_status
        end

        local output = process.stdout(handle)

        if output then
            local new_buf = ""

            for line in string.gmatch(`{buf}{str.from_bytes(output)}`, "([^\n\r]+)") do
                if not line then
                    continue
                end

                local jsonl_start = line:sub(1, 1) == "{"
                local jsonl_finish = line:sub(-1) == "}"

                -- If line contains json object then try to decode it and pass
                -- decoded object to the callback.
                if jsonl_start and jsonl_finish then
                    local status, message = pcall(str.decode, "json", line)

                    -- Decode may fail if the object has nested objects, and
                    -- the end of the outer object was not received yet
                    -- (something like "{"key": { "inner_key": 1 }").
                    --                  ^       ^                ^
                    if not status then
                        new_buf = line

                        break
                    end

                    callback(message)
                end

                -- If line starts as json object but it doesn't have the end
                -- of this object then we've read buffer partially. Store it
                -- to the buffer and try polling new stdout bytes.
                if jsonl_start and not jsonl_finish then
                    new_buf = line

                    break
                end
            end

            buf = new_buf
        end

        return false, nil
    end)
end

local __cache = {
    games = {} :: { [string]: GameInfo },
    components = {} :: { [string]: {GameComponentInfo} },
    versions = {} :: { [string]: {GameVersionInfo} },
    files = {} :: { [string]: {GameDownloadFileInfo} }
}

return function(binary_path: string?)
    local binary_path: string = binary_path or BINARY_PATH

    if not path.permissions(binary_path).write then
        error("sophon-tools module doesn't have access to the binary path")
    end

    local function ensure_process_api()
        if not process then
            error("sophon-tools module requires process API")
        end
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

        api = {
            games = function(options: ListGamesOptions?): Promise<{GameInfo}>
                local options: ListGamesOptions = options or {}

                local cache_key = if options.api then
                    `{options.api.region or "global"}-{options.api.launcher_id or "default"}`
                else
                    "global-default"

                if __cache.games[cache_key] then
                    return task.create(function() return true, clone(__cache.games[cache_key]) end)
                end

                ensure_process_api()

                local args = { "api", "list-games", "--output-format", "json" }

                append_api_options(options.api, args)
                append_network_options(options.network, args)

                ensure_verified_binary()

                local future = process.exec(binary_path, args)

                return task.create(function(): (boolean, any)
                    local status, result = future:poll()

                    if not status then
                        return false, nil
                    end

                    if not result.is_ok then
                        error("sophon-tools module failed to fetch games info")
                    end

                    if #result.stdout < 2 then
                        return true, {}
                    end

                    __cache.games[cache_key] = str.decode("json", str.trim(str.from_bytes(result.stdout)))

                    return true, clone(__cache.games[cache_key])
                end)
            end,

            components = function(options: ListGameComponentsOptions): Promise<{GameComponentInfo}>
                if not options
                    or not options.game_id
                    or typeof(options.game_id) ~= "string"
                    or #options.game_id == 0
                then
                    error("sophon-tools module didn't receive game identifier")
                end

                local cache_key = if options.api then
                    `{options.api.region or "global"}-{options.api.launcher_id or "default"}-{options.game_id}`
                else
                    `global-default-{options.game_id}`

                if __cache.components[cache_key] then
                    return task.create(function() return true, clone(__cache.components[cache_key]) end)
                end

                ensure_process_api()

                local args = {
                    "api", "list-components", options.game_id,
                    "--output-format", "json"
                }

                if options.show_all
                    and typeof(options.show_all) == "boolean"
                then
                    table.insert(args, "--show-all")
                    table.insert(args, if options.show_all then "true" else "false")
                end

                append_api_options(options.api, args)
                append_network_options(options.network, args)

                ensure_verified_binary()

                local future = process.exec(binary_path, args)

                return task.create(function(): (boolean, any)
                    local status, result = future:poll()

                    if not status then
                        return false, nil
                    end

                    if not result.is_ok then
                        error("sophon-tools module failed to fetch components info")
                    end

                    if #result.stdout < 2 then
                        return true, {}
                    end

                    __cache.components[cache_key] = str.decode("json", str.trim(str.from_bytes(result.stdout)))

                    return true, clone(__cache.components[cache_key])
                end)
            end,

            versions = function(options: ListGameVersionsOptions): Promise<{GameVersionInfo}>
                if not options
                    or not options.game_id
                    or typeof(options.game_id) ~= "string"
                    or #options.game_id == 0
                then
                    error("sophon-tools module didn't receive game identifier")
                end

                local cache_key = if options.api then
                    `{options.api.region or "global"}-{options.api.launcher_id or "default"}-{options.game_id}`
                else
                    `global-default-{options.game_id}`

                if __cache.versions[cache_key] then
                    return task.create(function() return true, clone(__cache.versions[cache_key]) end)
                end

                ensure_process_api()

                local args = {
                    "api", "game-versions", options.game_id,
                    "--output-format", "json"
                }

                append_api_options(options.api, args)
                append_network_options(options.network, args)

                ensure_verified_binary()

                local future = process.exec(binary_path, args)

                return task.create(function(): (boolean, any)
                    local status, result = future:poll()

                    if not status then
                        return false, nil
                    end

                    if not result.is_ok then
                        error("sophon-tools module failed to fetch versions info")
                    end

                    if #result.stdout < 2 then
                        return true, {}
                    end

                    __cache.versions[cache_key] = str.decode("json", str.trim(str.from_bytes(result.stdout)))

                    return true, clone(__cache.versions[cache_key])
                end)
            end,

            files = function(options: ListGameFilesOptions): Promise<{GameDownloadFileInfo}>
                if not options
                    or not options.game_id
                    or typeof(options.game_id) ~= "string"
                    or #options.game_id == 0
                then
                    error("sophon-tools module didn't receive game identifier")
                end

                local cache_key = if options.api then
                    `{options.api.region or "global"}-{options.api.launcher_id or "default"}-{options.game_id}-{options.component_id or "game"}-{options.version or "latest"}-{options.regex or "all"}`
                else
                    `global-default-{options.game_id}-game-latest-all`

                if __cache.files[cache_key] then
                    return task.create(function() return true, clone(__cache.files[cache_key]) end)
                end

                ensure_process_api()

                local args = {
                    "api", "game-download-info", options.game_id,
                    "--output-format", "json"
                }

                if options.component_id
                    and typeof(options.component_id) == "string"
                    and #options.component_id > 0
                then
                    table.insert(args, "--component-id")
                    table.insert(args, options.component_id)
                end

                if options.version
                    and typeof(options.version) == "string"
                    and #options.version > 0
                then
                    table.insert(args, "--version")
                    table.insert(args, options.version)
                end

                append_api_options(options.api, args)
                append_network_options(options.network, args)

                ensure_verified_binary()

                local future = process.exec(binary_path, args)

                return task.create(function(): (boolean, any)
                    local status, result = future:poll()

                    if not status then
                        return false, nil
                    end

                    if not result.is_ok then
                        error("sophon-tools module failed to fetch download info")
                    end

                    if #result.stdout < 2 then
                        return true, {}
                    end

                    __cache.files[cache_key] = str.decode("json", str.trim(str.from_bytes(result.stdout)))

                    return true, clone(__cache.files[cache_key])
                end)
            end
        },

        game = {
            detect = function(options: DetectGameOptions): Promise<DetectGameOptions?>
                if not options
                    or not options.game_dir
                    or typeof(options.game_dir) ~= "string"
                    or #options.game_dir == 0
                then
                    error("sophon-tools module didn't receive game directory")
                end

                if not path.permissions(options.game_dir).read then
                    error("sophon-tools module requires game directory read permissions to detect it")
                end

                ensure_process_api()

                local args = {
                    "detect", options.game_dir,
                    "--output-format", "json"
                }

                append_network_options(options.network, args)

                ensure_verified_binary()

                local future = process.exec(binary_path, args)

                return task.create(function(): (boolean, any)
                    local status, result = future:poll()

                    if not status then
                        return false, nil
                    end

                    if not result.is_ok then
                        error("sophon-tools module failed to detect installed game")
                    end

                    if #result.stdout < 2 then
                        return true, nil
                    end

                    return true, str.decode("json", str.trim(str.from_bytes(result.stdout)))
                end)
            end,

            verify = function(
                options: VerifyGameOptions,
                updater: (msg: VerifyGameMsg) -> ()
            ): Promise<boolean>
                if not options
                    or not options.game_id
                    or typeof(options.game_id) ~= "string"
                    or #options.game_id == 0
                then
                    error("sophon-tools module didn't receive game identifier")
                end

                if not options
                    or not options.game_dir
                    or typeof(options.game_dir) ~= "string"
                    or #options.game_dir == 0
                then
                    error("sophon-tools module didn't receive game directory")
                end

                if not updater or typeof(updater) ~= "function" then
                    error("sophon-tools module didn't receive updater callback")
                end

                if not path.permissions(options.game_dir).read then
                    error("sophon-tools module requires game directory read permissions to verify it")
                end

                ensure_process_api()

                local args = {
                    "verify", options.game_id, options.game_dir,
                    "--output-format", "json"
                }

                if options.component_id
                    and typeof(options.component_id) == "string"
                    and #options.component_id > 0
                then
                    table.insert(args, "--component-id")
                    table.insert(args, options.component_id)
                end

                if options.version
                    and typeof(options.version) == "string"
                    and #options.version > 0
                then
                    table.insert(args, "--version")
                    table.insert(args, options.version)
                end

                if options.regex
                    and typeof(options.regex) == "string"
                    and #options.regex > 0
                then
                    table.insert(args, "--regex")
                    table.insert(args, options.regex)
                end

                if options.fast_verify
                    and typeof(options.fast_verify) == "boolean"
                then
                    table.insert(args, "--fast-verify")
                    table.insert(args, if options.fast_verify then "true" else "false")
                end

                if options.show_missing
                    and typeof(options.show_missing) == "boolean"
                then
                    table.insert(args, "--show-missing")
                    table.insert(args, if options.show_missing then "true" else "false")
                end

                if options.threads
                    and typeof(options.threads) == "number"
                    and options.threads > 0
                then
                    table.insert(args, "--threads")
                    table.insert(args, tostring(options.threads))
                end

                append_api_options(options.api, args)
                append_network_options(options.network, args)

                ensure_verified_binary()

                return handle_process_jsonl_output(
                    process.open(binary_path, args),
                    function(message)
                        if message["available"] then
                            updater({
                                type = "available",
                                result = message["available"]["result"],
                                current = tonumber(message["available"]["current"]) or 0,
                                total = tonumber(message["available"]["total"]) or 0,
                                path = message["available"]["path"]
                            })
                        elseif message["missing"] then
                            updater({
                                type = "missing",
                                result = message["missing"]["result"],
                                path = message["missing"]["path"]
                            })
                        end
                    end
                )
            end,

            download = function(
                options: DownloadGameOptions,
                updater: (msg: DownloadGameMsg) -> ()
            ): Promise<boolean>
                if not options
                    or not options.game_id
                    or typeof(options.game_id) ~= "string"
                    or #options.game_id == 0
                then
                    error("sophon-tools module didn't receive game identifier")
                end

                if not options
                    or not options.game_dir
                    or typeof(options.game_dir) ~= "string"
                    or #options.game_dir == 0
                then
                    error("sophon-tools module didn't receive game directory")
                end

                if not updater or typeof(updater) ~= "function" then
                    error("sophon-tools module didn't receive updater callback")
                end

                if not path.permissions(options.game_dir).write then
                    error("sophon-tools module requires game directory write permissions to download into it")
                end

                ensure_process_api()

                local args = {
                    "download", options.game_id, options.game_dir,
                    "--output-format", "json"
                }

                if options.component_id
                    and typeof(options.component_id) == "string"
                    and #options.component_id > 0
                then
                    table.insert(args, "--component-id")
                    table.insert(args, options.component_id)
                end

                if options.version
                    and typeof(options.version) == "string"
                    and #options.version > 0
                then
                    table.insert(args, "--version")
                    table.insert(args, options.version)
                end

                if options.regex
                    and typeof(options.regex) == "string"
                    and #options.regex > 0
                then
                    table.insert(args, "--regex")
                    table.insert(args, options.regex)
                end

                if options.verify_manifest
                    and typeof(options.verify_manifest) == "string"
                    and #options.verify_manifest > 0
                then
                    table.insert(args, "--verify-manifest")
                    table.insert(args, options.verify_manifest)
                end

                if options.verify_chunks
                    and typeof(options.verify_chunks) == "string"
                    and #options.verify_chunks > 0
                then
                    table.insert(args, "--verify-chunks")
                    table.insert(args, options.verify_chunks)
                end

                if options.verify_before_downloading
                    and typeof(options.verify_before_downloading) == "string"
                    and #options.verify_before_downloading > 0
                then
                    table.insert(args, "--verify-before-downloading")
                    table.insert(args, options.verify_before_downloading)
                end

                if options.threads
                    and typeof(options.threads) == "number"
                    and options.threads > 0
                then
                    table.insert(args, "--threads")
                    table.insert(args, tostring(options.threads))
                end

                if options.target_memory_usage
                    and (
                        (typeof(options.target_memory_usage) == "string" and #options.target_memory_usage > 0)
                        or (typeof(options.target_memory_usage) == "number" and options.target_memory_usage > 0)
                    )
                then
                    table.insert(args, "--target-memory-usage")
                    table.insert(args, tostring(options.target_memory_usage))
                end

                if options.chunk_download_attempts
                    and typeof(options.chunk_download_attempts) == "number"
                    and options.chunk_download_attempts > 0
                then
                    table.insert(args, "--chunk-download-attempts")
                    table.insert(args, tostring(options.chunk_download_attempts))
                end

                if options.fetch_manifest_timeout
                    and (
                        (typeof(options.fetch_manifest_timeout) == "string" and #options.fetch_manifest_timeout > 0)
                        or (typeof(options.fetch_manifest_timeout) == "number" and options.fetch_manifest_timeout > 0)
                    )
                then
                    table.insert(args, "--fetch-manifest-timeout")
                    table.insert(args, tostring(options.fetch_manifest_timeout))
                end

                if options.fetch_chunk_per_mb_timeout
                    and (
                        (typeof(options.fetch_chunk_per_mb_timeout) == "string" and #options.fetch_chunk_per_mb_timeout > 0)
                        or (typeof(options.fetch_chunk_per_mb_timeout) == "number" and options.fetch_chunk_per_mb_timeout > 0)
                    )
                then
                    table.insert(args, "--fetch-chunk-per-mb-timeout")
                    table.insert(args, tostring(options.fetch_chunk_per_mb_timeout))
                end

                append_api_options(options.api, args)
                append_network_options(options.network, args)

                ensure_verified_binary()

                return handle_process_jsonl_output(
                    process.open(binary_path, args),
                    function(message)
                        if message["verify"] then
                            updater({
                                type = "verify",
                                result = message["verify"]["result"],
                                current = message["verify"]["current"],
                                total = message["verify"]["total"],
                                path = message["verify"]["path"]
                            })
                        elseif message["download"] then
                            updater({
                                type = "download",
                                current = message["download"]["current"],
                                total = message["download"]["total"]
                            })
                        end
                    end
                )
            end,

            update = function(
                options: UpdateGameOptions,
                updater: (msg: UpdateGameMsg) -> ()
            ): Promise<boolean>
                if not options
                    or not options.game_id
                    or typeof(options.game_id) ~= "string"
                    or #options.game_id == 0
                then
                    error("sophon-tools module didn't receive game identifier")
                end

                if not options
                    or not options.game_dir
                    or typeof(options.game_dir) ~= "string"
                    or #options.game_dir == 0
                then
                    error("sophon-tools module didn't receive game directory")
                end

                if not updater or typeof(updater) ~= "function" then
                    error("sophon-tools module didn't receive updater callback")
                end

                if not path.permissions(options.game_dir).write then
                    error("sophon-tools module requires game directory write permissions to update it")
                end

                ensure_process_api()

                local args = {
                    "update", options.game_id, options.game_dir,
                    "--output-format", "json",
                    "--chunks-dir"
                }

                if options.chunks_dir
                    and typeof(options.chunks_dir) == "string"
                    and #options.chunks_dir
                then
                    if options.chunks_dir and not path.permissions(options.chunks_dir).write then
                        error("sophon-tools module requires chunks directory write permissions to use it")
                    end

                    table.insert(args, tostring(options.chunks_dir))
                else
                    table.insert(args, CACHE_DIR)
                end

                if options.component_id
                    and typeof(options.component_id) == "string"
                    and #options.component_id > 0
                then
                    table.insert(args, "--component-id")
                    table.insert(args, options.component_id)
                end

                if options.from_version
                    and typeof(options.from_version) == "string"
                    and #options.from_version > 0
                then
                    table.insert(args, "--from-version")
                    table.insert(args, options.from_version)
                end

                if options.to_version
                    and typeof(options.to_version) == "string"
                    and #options.to_version > 0
                then
                    table.insert(args, "--to-version")
                    table.insert(args, options.to_version)
                end

                if options.regex
                    and typeof(options.regex) == "string"
                    and #options.regex > 0
                then
                    table.insert(args, "--regex")
                    table.insert(args, options.regex)
                end

                if options.verify_manifest
                    and typeof(options.verify_manifest) == "string"
                    and #options.verify_manifest > 0
                then
                    table.insert(args, "--verify-manifest")
                    table.insert(args, options.verify_manifest)
                end

                if options.verify_chunks
                    and typeof(options.verify_chunks) == "string"
                    and #options.verify_chunks > 0
                then
                    table.insert(args, "--verify-chunks")
                    table.insert(args, options.verify_chunks)
                end

                if options.verify_before_updating
                    and typeof(options.verify_before_updating) == "string"
                    and #options.verify_before_updating > 0
                then
                    table.insert(args, "--verify-before-updating")
                    table.insert(args, options.verify_before_updating)
                end

                if options.verify_before_patching
                    and typeof(options.verify_before_patching) == "string"
                    and #options.verify_before_patching > 0
                then
                    table.insert(args, "--verify-before-patching")
                    table.insert(args, options.verify_before_patching)
                end

                if options.delete_unused_assets
                    and typeof(options.delete_unused_assets) == "boolean"
                then
                    table.insert(args, "--delete-unused-assets")
                    table.insert(args, if options.delete_unused_assets then "true" else "false")
                end

                if options.patch_assets
                    and typeof(options.patch_assets) == "boolean"
                then
                    table.insert(args, "--patch-assets")
                    table.insert(args, if options.patch_assets then "true" else "false")
                end

                if options.delete_applied_chunks
                    and typeof(options.delete_applied_chunks) == "boolean"
                then
                    table.insert(args, "--delete-applied-chunks")
                    table.insert(args, if options.delete_applied_chunks then "true" else "false")
                end

                if options.repair_broken_assets
                    and typeof(options.repair_broken_assets) == "string"
                    and #options.repair_broken_assets > 0
                then
                    table.insert(args, "--repair-broken-assets")
                    table.insert(args, options.repair_broken_assets)
                end

                if options.threads
                    and typeof(options.threads) == "number"
                    and options.threads > 0
                then
                    table.insert(args, "--threads")
                    table.insert(args, tostring(options.threads))
                end

                if options.target_memory_usage
                    and (
                        (typeof(options.target_memory_usage) == "string" and #options.target_memory_usage > 0)
                        or (typeof(options.target_memory_usage) == "number" and options.target_memory_usage > 0)
                    )
                then
                    table.insert(args, "--target-memory-usage")
                    table.insert(args, tostring(options.target_memory_usage))
                end

                if options.chunk_download_attempts
                    and typeof(options.chunk_download_attempts) == "number"
                    and options.chunk_download_attempts > 0
                then
                    table.insert(args, "--chunk-download-attempts")
                    table.insert(args, tostring(options.chunk_download_attempts))
                end

                if options.fetch_manifest_timeout
                    and (
                        (typeof(options.fetch_manifest_timeout) == "string" and #options.fetch_manifest_timeout > 0)
                        or (typeof(options.fetch_manifest_timeout) == "number" and options.fetch_manifest_timeout > 0)
                    )
                then
                    table.insert(args, "--fetch-manifest-timeout")
                    table.insert(args, tostring(options.fetch_manifest_timeout))
                end

                if options.fetch_chunk_per_mb_timeout
                    and (
                        (typeof(options.fetch_chunk_per_mb_timeout) == "string" and #options.fetch_chunk_per_mb_timeout > 0)
                        or (typeof(options.fetch_chunk_per_mb_timeout) == "number" and options.fetch_chunk_per_mb_timeout > 0)
                    )
                then
                    table.insert(args, "--fetch-chunk-per-mb-timeout")
                    table.insert(args, tostring(options.fetch_chunk_per_mb_timeout))
                end

                append_api_options(options.api, args)
                append_network_options(options.network, args)

                ensure_verified_binary()

                return handle_process_jsonl_output(
                    process.open(binary_path, args),
                    function(message)
                        if message["updater"] and message["updater"]["verify"] then
                            updater({
                                type = "updater-verify",
                                result = message["updater"]["verify"]["result"],
                                current = message["updater"]["verify"]["current"],
                                total = message["updater"]["verify"]["total"],
                                path = message["updater"]["verify"]["path"]
                            })
                        elseif message["updater"] and message["updater"]["download"] then
                            updater({
                                type = "updater-download",
                                current = message["updater"]["download"]["current"],
                                total = message["updater"]["download"]["total"]
                            })
                        elseif message["updater"] and message["updater"]["patch"] then
                            updater({
                                type = "updater-patch",
                                result = message["updater"]["patch"]["current"],
                                current = message["updater"]["patch"]["current"],
                                total = message["updater"]["patch"]["total"],
                                path = message["updater"]["patch"]["path"]
                            })
                        elseif message["repairer"] and message["repairer"]["verify"] then
                            updater({
                                type = "repairer-verify",
                                result = message["repairer"]["verify"]["result"],
                                current = message["repairer"]["verify"]["current"],
                                total = message["repairer"]["verify"]["total"],
                                path = message["repairer"]["verify"]["path"]
                            })
                        elseif message["repairer"] and message["repairer"]["download"] then
                            updater({
                                type = "repairer-download",
                                current = message["repairer"]["download"]["current"],
                                total = message["repairer"]["download"]["total"]
                            })
                        end
                    end
                )
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
