-- components/wine v0.0.0
-- Copyright (C) 2025  Nikita Podvirnyi <krypt0nn@vk.com>
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
    binary: string,
    env: table | nil
}

type Output = {
    -- Exit code of the process.
    status: number | null,

    -- Was the process closed normally.
    is_ok: boolean,

    -- Output of the process.
    stdout: {number},
    stderr: {number}
}

type LaunchCommand = {
    binary: string,
    args: {string} | nil,
    env: table | nil
}

local data_dir_path = path.persist_dir("components")
local wine_dir_path = path.join(data_dir_path, "wine")

return function(imports)
    local wine_versions_cache = nil

    -- List all the available wine groups and their versions.
    local function get_versions()
        if not wine_versions_cache then
            wine_versions_cache = {}

            local groups = {
                { name = "wine_staging_tkg", title = "Wine-Staging-TkG", src = imports.wine_staging_tkg }
            }

            for _, group in groups do
                table.insert(wine_versions_cache, {
                    name = group.name,
                    title = group.title,
                    versions = str.decode(str.from_bytes(group.src), "json")
                })
            end
        end

        return clone(wine_versions_cache)
    end

    -- Try to find features of the wine version with provided name.
    local function get_version_features(name: string): Features | nil
        for _, group in pairs(get_versions()) do
            for _, version in pairs(group.versions) do
                if version.name == name then
                    return version.features
                end
            end
        end

        return nil
    end

    -- Run wine with provided name, arguments and environment variables.
    -- Return true if command run successfully, otherwise false.
    local function run(name: string, args: {string}, env: table | nil): Output | nil
        if not process then
            error("components library has no access to the v1 process API")
        end

        local features = get_version_features(name)

        if not features then
            error(`invalid wine version name: '{name}'`)
        end

        local wine_path = path.join(wine_dir_path, name, features.binary)

        if not fs.exists(wine_path) then
            error(`wine version '{name}' is not installed or invalid`)
        end

        if not env then
            env = {}
        end

        if features.env then
            for k, v in pairs(features.env) do
                env[k] = v
            end
        end

        return process.exec(wine_path, args, env)
    end

    -- Check if provided folder contains a valid wine prefix.
    local function is_valid_prefix(prefix: string): boolean
        return fs.exists(path.join(prefix, "drive_c")) and fs.exists(path.join(prefix, "system.reg"))
    end

    -- Create or update wine prefix with provided version name and prefix path.
    local function update_prefix(name: string, prefix: string)
        if not path.accessible(prefix) then
            error(`you are not allowed to create wine prefix in '{prefix}'`)
        end

        local result = run(name, { "wineboot" }, { WINEPREFIX = prefix })

        if result.is_ok and is_valid_prefix(prefix) then
            fs.write_file(path.join(prefix, ".wine"), name)
        end
    end

    -- Read name of the wine used to create prefix in the given folder.
    local function get_prefix_wine_name(prefix: string): string | nil
        local path = path.join(prefix, ".wine")

        if not fs.exists(path) then
            return nil
        end

        return str.from_bytes(fs.read_file(path))
    end

    -- Wrap provided launch command with selected wine version and prefix path.
    -- Basically adds `wine` to the beginning of the command and merges
    -- environment variables.
    local function wrap_launch_command(name: string, prefix: string, command: LaunchCommand): LaunchCommand
        if not path.accessible(prefix) then
            error(`you are not allowed to create wine prefix in '{prefix}'`)
        end

        local features = get_version_features(name)

        if not features then
            error(`invalid wine version name: '{name}'`)
        end

        local original_binary = command.binary
        local original_args = command.args or {}

        command.binary = path.join(wine_dir_path, name, features.binary)
        command.args = { original_binary }
        command.env = command.env or {}

        for _, arg in ipairs(original_args) do
            table.insert(command.args, arg)
        end

        if features.env then
            for k, v in pairs(features.env) do
                command.env[k] = v
            end
        end

        command.env["WINEPREFIX"] = prefix

        return command
    end

    return {
        versions = {
            list = get_versions,
            get_features = get_version_features
        },
        prefix = {
            is_valid = is_valid_prefix,
            update = update_prefix,
            get_wine_name = get_prefix_wine_name
        },
        wrap_launch_command = wrap_launch_command
    }
end
