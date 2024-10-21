-- semver v1.0.0
-- Copyright (C) 2024  Nikita Podvirnyi <krypt0nn@vk.com>
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

type Semver = { major: number, minor: number, patch: number }

local function parse_version(version: string): Semver | nil
    local numbers = version:gmatch("([1-9]+)%.([0-9]+)%.([0-9]+)")

    for major, minor, patch in numbers do
        return {
            major = major,
            minor = minor,
            patch = patch
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

local __semver = {
    __add = function(version_1: Semver, version_2: Semver): Semver | nil
        version_1.major += version_2.major
        version_1.minor += version_2.minor
        version_1.patch += version_2.patch

        return version_1
    end,

    __sub = function(version_1: Semver, version_2: Semver): Semver | nil
        version_1.major -= version_2.major
        version_1.minor -= version_2.minor
        version_1.patch -= version_2.patch

        return version_1
    end,

    __tostring = function(version: Semver): string
        return version.major .. "." .. version.minor .. "." .. version.patch
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
}

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
return function(version: string): Semver | nil
    local version = parse_version(version)

    if not version then
        return nil
    end

    setmetatable(version, __semver)

    return version
end
