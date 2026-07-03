-- umu-launcher v0.2.2
-- Copyright (C) 2026 Nikita Podvirnyi <krypt0nn@dawn.wine>
--                    NelloKudo <marshnelloosu@gmail.com>
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

type LaunchInfo = {
    binary: string,
    args: { string },
    env: { [string]: string }
}

type VerifyResult =
    | "success"
    | "invalid_binary"
    | "missing_python3"

local DOWNLOAD_INFO = {
    url = "https://github.com/Open-Wine-Components/umu-launcher/releases/download/1.4.0/umu-launcher-1.4.0-zipapp.tar",
    size = 419043,
    hash = "blake3:ifym7x75nzqxvb3xgd5aqw7yku6vuizgwmdgx2i25eyr7tmgexwq===="
}

return function(umu_binary: string)
    if not umu_binary then
        umu_binary = path.join(path.temp_dir(), "umu-run")
    end

    if not path.permissions(umu_binary).read then
        error("umu-launcher module doesn't have access to the umu-run binary")
    end

    local verifier = import("verifier")

    if not verifier then
        error("umu-launcher became a package, use package.json in inputs")
    end

    return {
        umu = {
            path = clone(umu_binary),

            -- Download and extract umu-run binary. Return path to installed
            -- binary or throw an error if downloading has failed.
            --
            -- Note that this method *does not* verify if this binary is already
            -- installed.
            install = function(updater: (current: number, total: number, action: "download" | "extract") -> ()): string
                local umu_temp_download_path: string = path.join(path.temp_dir(), `umu-{DOWNLOAD_INFO.hash or "unknown"}.tar`)
                local umu_temp_extract_path: string  = path.join(path.temp_dir(), `umu-launcher-{DOWNLOAD_INFO.hash or "unknown"}`)
                local umu_temp_binary_path: string   = path.join(umu_temp_extract_path, "umu", "umu-run")

                -- Delete temporary files

                if fs.exists(umu_binary) then
                    fs.remove(umu_binary):await()
                end

                if fs.exists(umu_temp_download_path) then
                    fs.remove(umu_temp_download_path):await()
                end

                if fs.exists(umu_temp_extract_path) then
                    fs.remove(umu_temp_extract_path):await()
                end

                -- Download umu-launcher archive

                updater(0, 0, "download") -- hint "download" updater mode

                local handle = downloader.create()

                local task = downloader.download(handle, {
                    url = DOWNLOAD_INFO.url,
                    output_file = umu_temp_download_path,
                    continue_download = false, -- 420 KB total, can redownload easily
                    on_update = function(current: number, total: number)
                        updater(current, total, "download")
                    end
                })

                downloader.wait(task)
                downloader.close(handle)

                -- Extract umu-launcher archive

                updater(0, 0, "extract") -- hint "extract" updater mode

                local handle = archive.open(umu_temp_download_path)

                local result = archive.extract(
                    handle,
                    umu_temp_extract_path,
                    function(current, total)
                        updater(current, total, "extract")
                    end
                )

                archive.close(handle)

                if not result then
                    error("failed to extract umu-launcher archive")
                end

                if not verifier({
                    path = umu_temp_binary_path,
                    size = DOWNLOAD_INFO.size,
                    hash = DOWNLOAD_INFO.hash
                }):await() then
                    error("downloaded umu-launcher binary has invalid hash")
                end

                fs.create_dir(path.parent(umu_binary)):await()

                fs.move(umu_temp_binary_path, umu_binary):await()

                fs.remove(umu_temp_download_path):await()
                fs.remove(umu_temp_extract_path):await()

                return umu_binary
            end,

            -- Verify installed umu-launcher binary hash.
            verify = function(): (boolean, VerifyResult)
                -- verify the umu-launcher's binary hash.
                if not verifier({
                    path = umu_binary,
                    size = DOWNLOAD_INFO.size,
                    hash = DOWNLOAD_INFO.hash
                }):await() then
                    return false, "invalid_binary"
                end

                -- python3 is required to run umu-launcher.
                if not system.find("python3") then
                    return false, "missing_python3"
                end

                return true, "success"
            end,

            -- Wrap binary launch info to use umu-launcher binary.
            wrap = function(info: LaunchInfo): LaunchInfo
                if not info then
                    error("no launch info provided to the umu-launcher module")
                end

                if not info.binary then
                    error("no launch binary info provided to the umu-launcher module")
                end

                if not info.args or typeof(info.args) ~= "table" then
                    info.args = {}
                end

                if not info.env or typeof(info.env) ~= "table" then
                    info.env = {}
                end

                local wrapped_info = {
                    binary = umu_binary,
                    args = { info.binary },
                    env = info.env
                }

                for _, arg in ipairs(info.args) do
                    table.insert(wrapped_info.args, arg)
                end

                return wrapped_info
            end
        },

        prefix = {
            -- Try to create a proton prefix using umu-launcher.
            create = function(proton_path: string, prefix_path: string): boolean
                if not path.permissions(proton_path).read then
                    error("umu-launcher module doesn't have access to the given proton build folder path")
                end

                if not path.permissions(prefix_path).write then
                    error("umu-launcher module doesn't have access to the given proton prefix path")
                end

                if not verifier({
                    path = umu_binary,
                    size = DOWNLOAD_INFO.size,
                    hash = DOWNLOAD_INFO.hash
                }):await() then
                    error("invalid umu-launcher binary hash")
                end

                local handle = process.open(umu_binary, { "wineboot", "-u" }, {
                    PROTONPATH       = proton_path,
                    WINEPREFIX       = path.join(prefix_path, "pfx"),
                    PROTON_USE_WOW64 = "1"
                })

                local output = process.wait(handle)

                if not output.is_ok then
                    error("umu-launcher module failed to create proton prefix")
                end

                return fs.exists(path.join(prefix_path, "pfx", "drive_c"))
            end,

            -- Verify proton prefix using umu-launcher.
            verify = function(prefix_path: string)
                return fs.exists(path.join(prefix_path, "pfx", "drive_c"))
            end
        }
    }
end
