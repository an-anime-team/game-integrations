-- components/dxvk v0.1.3
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

type Features = {
    env: { [string]: string }?
}

type DxvkInfo = {
    name: string,
    arch: string
}

type LaunchCommand = {
    binary: string,
    args: { string }?,
    env: { [string]: string }?
}

local data_dir_path: string = path.persist_dir("components")
local dxvk_dir_path: string = path.join(data_dir_path, "dxvk")

return function(imports)
    local dxvk_versions_cache = nil

    -- List all the available dxvk groups and their versions.
    local function get_versions()
        if not dxvk_versions_cache then
            dxvk_versions_cache = {}

            for _, group in imports do
                table.insert(dxvk_versions_cache, {
                    name = group.name,
                    title = group.title,
                    versions = str.decode("json", str.from_bytes(group.src))
                })
            end
        end

        return clone(dxvk_versions_cache)
    end

    -- Try to find features of the dxvk version with provided name.
    -- This function will return empty table if version exists but it has no features.
    local function get_version_features(name: string): Features?
        for _, group in pairs(get_versions()) do
            for _, version in pairs(group.versions) do
                if version.name == name then
                    return version.features or {}
                end
            end
        end

        return nil
    end

    -- Install DXVK to the given wine prefix folder.
    local function install(name: string, prefix: string, arch: "x32" | "x64")
        local system32_dir_path: string  = path.join(prefix, "drive_c", "windows", "system32")
        local dxvk_arch_dir_path: string = path.join(dxvk_dir_path, name, arch)

        if not fs.exists(path.join(dxvk_arch_dir_path, "d3d11.dll")) then
            error(`can't install invalid dxvk arch '{arch}' or version name '{name}'`)
        end

        if not fs.exists(path.join(system32_dir_path, "cmd.exe")) then
            error(`can't install dxvk to invalid wine prefix system32 folder: '{system32_dir_path}'`)
        end

        for _, entry in fs.read_dir(dxvk_arch_dir_path):await() do
            if entry.type == "file" and string.match(entry.name, ".+%.dll") then
                local prefix_file_path = path.join(system32_dir_path, entry.name)

                if fs.exists(prefix_file_path) then
                    fs.remove(prefix_file_path):await()
                end

                fs.move(entry.path, prefix_file_path):await()
            end
        end

        fs.write_file(
            path.join(prefix, ".dxvk"),
            str.encode("json", { name = name, arch = arch })
        ):await()
    end

    -- Read name and arch of the dxvk version applied to the prefix.
    local function get_prefix_dxvk_info(prefix: string): DxvkInfo | nil
        local path = path.join(prefix, ".dxvk")

        if not fs.exists(path) then
            return nil
        end

        return str.decode("json", str.from_bytes(fs.read_file(path):await()))
    end

    -- Wrap provided launch command with selected wine version name.
    -- Basically adds `wine` to the beginning of the command and merges
    -- environment variables.
    local function wrap_launch_command(name: string, command: LaunchCommand): LaunchCommand
        local features = get_version_features(name)

        if not features then
            error(`invalid dxvk version name: '{name}'`)
        end

        if features.env then
            local env = command.env or {}

            for k, v in pairs(features.env) do
                env[k] = v
            end

            command.env = env
        end

        return command
    end

    return {
        versions = {
            list = get_versions,
            get_features = get_version_features
        },
        prefix = {
            get_info = get_prefix_dxvk_info
        },
        install = install,
        wrap_launch_command = wrap_launch_command
    }
end
