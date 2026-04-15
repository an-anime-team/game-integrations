-- umu-launcher v0.1.1
-- Copyright (C) 2026 Nikita Podvirnyi <krypt0nn@vk.com>
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

type LaunchInfo = {
    binary: string,
    args: { string },
    env: { [string]: string }
}

type VerifyResult =
    | "success"
    | "invalid_hash"
    | "missing_python3_binary"
    | "missing_bwrap_binary"

local umu_info = {
    url = "https://github.com/Open-Wine-Components/umu-launcher/releases/download/1.4.0/umu-launcher-1.4.0-zipapp.tar",
    version = "1.4.0",
    hash = "1383ead8ce563197"
}

local function verify_umu_binary(umu_path: string): boolean
    if not path.exists(umu_path) then
        return false
    end

    local umu_hash = hash.digitize_file("seahash", umu_path):await()

    umu_hash = str.encode("hex", umu_hash)

    if #umu_info.hash == 0 then
        dbg(`seahash("{umu_path}") = "{umu_hash}"`)

        return false
    else
        return umu_hash == umu_info.hash
    end
end

return function(umu_binary: string)
    if not umu_binary then
        umu_binary = path.join(path.temp_dir(), "umu-run")
    end

    if not path.permissions(umu_binary).read then
        error("umu-launcher module doesn't have access to the umu-run binary")
    end

    local function ensure_verified_umu()
        if not verify_umu_binary(umu_binary) then
            error("invalid umu-launcher binary hash")
        end
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
                local umu_temp_download_path: string = path.join(path.temp_dir(), `umu-{umu_info.version}.tar`)
                local umu_temp_extract_path: string  = path.join(path.temp_dir(), `umu-launcher-{umu_info.version}`)
                local umu_temp_binary_path: string   = path.join(umu_temp_extract_path, "umu", "umu-run")

                -- Delete temporary files

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
                    url = umu_info.url,
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

                if not verify_umu_binary(umu_temp_binary_path) then
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
                -- verify the umu-launcher's binary hash
                if not verify_umu_binary(umu_binary) then
                    return false, "invalid_hash"
                end

                -- python3 binary is required to run umu-launcher
                if not system.find("python3") then
                    return false, "missing_python3_binary"
                end

                -- bwrap binary is required to run umu-launcher
                if not system.find("bwrap") then
                    return false, "missing_bwrap_binary"
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

                ensure_verified_umu()

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
