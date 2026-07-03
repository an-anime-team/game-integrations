-- semver v1.0.2
-- Copyright (C) 2024 - 2025  Nikita Podvirnyi <krypt0nn@dawn.wine>
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

type Semver = {
    major: number,
    minor: number,
    patch: number
}

type SemverMetatable = typeof(setmetatable({} :: Semver, {} :: {
    __tostring: (version: Semver) -> string,
    __add: (version_1: Semver, version_2: Semver) -> Semver,
    __sub: (version_1: Semver, version_2: Semver) -> Semver,
    __eq: (version_1: Semver, version_2: Semver) -> boolean,
    __lt: (version_1: Semver, version_2: Semver) -> boolean,
    __le: (version_1: Semver, version_2: Semver) -> boolean
}))

local function parse_version(version: string): Semver?
    local numbers = version:gmatch("([0-9]+)%.([0-9]+)%.([0-9]+)")

    for major, minor, patch in numbers do
        return {
            major = tonumber(major) or 0,
            minor = tonumber(minor) or 0,
            patch = tonumber(patch) or 0
        }
    end

    return nil
end

-- [ 1] if version_1 > version_2
-- [ 0] if version_1 = version_2
-- [-1] if version_1 < version_2
local function compare_versions(version_1: Semver, version_2: Semver): number
    if version_1.major > version_2.major then return  1 end
    if version_1.major < version_2.major then return -1 end

    if version_1.minor > version_2.minor then return  1 end
    if version_1.minor < version_2.minor then return -1 end

    if version_1.patch > version_2.patch then return  1 end
    if version_1.patch < version_2.patch then return -1 end

    return 0
end

-- Example:
--
-- local semver = import("semver")
--
-- local a = semver("1.2.0")
-- local b = semver("2.3.1")
--
-- print(a)      -- "1.2.0"
-- print(a > b)  -- false
-- print(a <= b) -- true
-- print(a + b)  -- "3.5.1"
-- print(b - a)  -- "1.1.1"
return function(version: Semver | string | nil): SemverMetatable?
    if type(version) == "string" then
        version = parse_version(version)
    end

    if typeof(version) == "table" then
        setmetatable(version, {
            __tostring = function(version: Semver): string
                return `{version.major}.{version.minor}.{version.patch}`
            end,

            __add = function(version_1: SemverMetatable, version_2: Semver): SemverMetatable
                local new_version = {
                    major = version_1.major + version_2.major,
                    minor = version_1.minor + version_2.minor,
                    patch = version_1.patch + version_2.patch
                }

                setmetatable(new_version, getmetatable(version_1))

                return new_version
            end,

            __sub = function(version_1: SemverMetatable, version_2: Semver): SemverMetatable
                local new_version = {
                    major = version_1.major - version_2.major,
                    minor = version_1.minor - version_2.minor,
                    patch = version_1.patch - version_2.patch
                }

                setmetatable(new_version, getmetatable(version_1))

                return new_version
            end,

            __eq = function(version_1: Semver, version_2: Semver): boolean
                return compare_versions(version_1, version_2) == 0
            end,

            __lt = function(version_1: Semver, version_2: Semver): boolean
                return compare_versions(version_1, version_2) == -1
            end,

            __le = function(version_1: Semver, version_2: Semver): boolean
                return compare_versions(version_1, version_2) <= 0
            end
        })
    end

    return version :: SemverMetatable
end
