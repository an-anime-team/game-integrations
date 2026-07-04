-- semver v1.0.2
-- Copyright (C) 2024 - 2025  Nikita Podvirnyi <krypt0nn@dawn.wine>
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
