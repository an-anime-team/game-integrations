-- nixos-command-wrapper v0.1.0
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

type LaunchInfo = {
    status: string?,
    hint: { [string]: string }?,
    binary: string,
    args: {string}?,
    env: { [string]: string }?
}

local __is_nixos = path.exists("/etc/NIXOS")
local __has_steam_run = nil

if __is_nixos then
    __has_steam_run = system.find("steam-run") ~= nil
end

return function(launch_info: LaunchInfo): LaunchInfo
    if not __is_nixos then
        return launch_info
    end

    if not __has_steam_run then
        launch_info.status = "warning"

        launch_info.hint = {
            en = "To launch the game on NixOS you need to have steam-run binary, but it is not available on your system",
            ru = "Для запуска игры на NixOS требуется steam-run, но он не был обнаружен в вашей системе"
        }

        return launch_info
    end

    local args = { launch_info.binary }

    for _, arg in ipairs(launch_info.args or {}) do
        table.insert(args, arg)
    end

    return {
        binary = "steam-run",
        args = args,
        env = launch_info.env
    }
end
