-- hyvlib v0.0.0
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

local semver = import("semver")
local iter = import("iterable")

local editions_locales = {
    global = {
        en = "Global",
        ru = "Глобальная",
        zh = "全球"
    },

    china = {
        en = "Chinese",
        ru = "Китайская",
        zh = "中文"
    }
}

local games = {
    genshin = {
        editions = {
            global = {
                api_url = "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getGamePackages?launcher_id=VYTpXlbWo8",
                game_id = "hk4e_global",
                title = editions_locales.global
            },

            china = {
                api_url = "https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGamePackages?launcher_id=jGHBHlcOq1",
                game_id = "hk4e_cn",
                title = editions_locales.china
            }
        }
    },

    zzz = {
        editions = {
            global = {
                api_url = "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getGamePackages?launcher_id=VYTpXlbWo8",
                game_id = "nap_global",
                title = editions_locales.global
            },

            china = {
                api_url = "https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGamePackages?launcher_id=jGHBHlcOq1",
                game_id = "nap_cn",
                title = editions_locales.china
            }
        }
    },

    hsr = {
        editions = {
            global = {
                api_url = "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getGamePackages?launcher_id=VYTpXlbWo8",
                game_id = "hkrpg_global",
                title = editions_locales.global
            },

            china = {
                api_url = "https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGamePackages?launcher_id=jGHBHlcOq1",
                game_id = "hkrpg_cn",
                title = editions_locales.china
            }
        }
    },

    honkai = {
        editions = {
            global = {
                api_url = "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getGamePackages?launcher_id=VYTpXlbWo8",
                game_id = "bh3_global",
                title = editions_locales.global
            },

            china = {
                api_url = "https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGamePackages?launcher_id=jGHBHlcOq1",
                game_id = "bh3_cn",
                title = editions_locales.china
            }
        }
    }
}

-- Declared in the semver package
type Semver = { major: number, minor: number, patch: number }

type Api = {
    version: Semver,
    segments: { Segment },
    voiceovers: { Voiceover },
    extracted_url: string,
    patches: { Patch }
}

type Segment = {
    url: string,
    md5: string,
    download_size: number,
    extracted_size: number
}

type Voiceover = {
    language: string,
    url: string,
    md5: string,
    download_size: number,
    extracted_size: number
}

type Patch = {
    version: Semver,
    segments: { Segment },
    voiceovers: { Voiceover }
}

local api_cache = nil

-- hyvlib.api.get()
-- Try to fetch the HYVse API
local function api_get(url: string, id: string): Api?
    if not api_cache[url] then
        local response = net.fetch(api_url)

        if not response.is_ok then
            error("API request failed: HTTP code " .. response.status)
        end

        api_cache[url] = str.decode(str.from_bytes(response.body), "json")
    end

    local scope = iter(api_cache[url].data.game_packages)
        .find(function(game)
            return string.find(game.game.biz, id) or string.find(game.game.id, id)
        end)

    if not scope then
        return nil
    end

    local response = clone(scope.value)

    return {
        version = semver(response.main.major.version) or error(`failed to parse semver game version from '{response.main.major.version}'`),

        segments = iter(response.main.major.game_pkgs)
            .map(function(package)
                return {
                    url = package.url,
                    md5 = package.md5,
                    download_size = package.size + 0,
                    extracted_size = package.decompressed_size + 0
                }
            end)
            .collect(),

        voiceovers = iter(response.main.major.audio_pkgs)
            .map(function(package)
                return {
                    language = package.language,
                    url = package.url,
                    md5 = package.md5,
                    download_size = package.size + 0,
                    extracted_size = package.decompressed_size + 0
                }
            end)
            .collect(),

        extracted_url = response.main.major.res_list_url,

        patches = iter(response.main.patches)
            .map(function(patch)
                return {
                    version = semver(patch.version) or error(`failed to parse semver patch version from '{patch.version}'`),

                    segments = iter(patch.game_pkgs)
                        .map(function(package)
                            return {
                                url = package.url,
                                md5 = package.md5,
                                download_size = package.size + 0,
                                extracted_size = package.decompressed_size + 0
                            }
                        end)
                        .collect(),

                    voiceovers = iter(patch.audio_pkgs)
                        .map(function(package)
                            return {
                                language = package.language,
                                url = package.url,
                                md5 = package.md5,
                                download_size = package.size + 0,
                                extracted_size = package.decompressed_size + 0
                            }
                        end)
                        .collect()
                }
            end)
            .collect()
    }
end

return iter(games)
    .map(function(game)
        return iter(game.editions)
            .map(function(edition)
                return {
                    api = {
                        get = function()
                            return api_get(edition.api_url, edition.game_id)
                        end
                    }
                }
            end)
            .collect()
    end)
    .collect()
