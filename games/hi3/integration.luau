-- HI3rd integration v0.0.0
-- Copyright (C) 2025  Nikita Podvirnyi <krypt0nn@dawn.wine>
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

type Variant = {
    platform: string,
    edition: string
}

local hyvlib = import("hyvlib").hyvlib("hi3")
local i18n = import("i18n").i18n

---------------------------------------
-- Game install management

local function game_folder(edition: string)
    -- TODO: proper implementation

    return path.join(path.persist_dir("honkai_impact_3rd"), "Honkai Impact 3rd " .. edition)
end

local function game_object(edition: string)
    return hyvlib(edition).open_game_folder(game_folder(edition))
end

---------------------------------------
-- Module

return {
    standard = 1,

    editions = function(platform: string)
        return {
            { name = "global", title = i18n("global_game_edition") },
            { name = "sea",    title = i18n("sea_game_edition")    },
            { name = "china",  title = i18n("china_game_edition")  },
            { name = "taiwan", title = i18n("taiwan_game_edition") },
            { name = "japan",  title = i18n("japan_game_edition")  },
            { name = "korea",  title = i18n("korea_game_edition")  }
        }
    end,

    game = {
        get_status = function(variant: Variant)
            local game = game_object(variant.edition)

            if not game:is_installed() then
                return "not-installed"
            end

            if not game:get_installed_version() then
                error("No version file, not supported yet")
            end

            if game:is_update_required(nil) then
                return "update-required"
            end

            return "installed"
        end,

        get_diff = function(variant: Variant)
            local game = game_object(variant.edition)

            return game:make_update_diff(path.temp_dir(), nil)
        end,

        get_launch_info = function(variant: Variant)
            return {
                status = "disabled",
                hint = {
                    en = "It's a test implementation not meant for real use",
                    ru = "Это тестовая реализация, не предназначенная для реального использования"
                },
                binary = ""
            }
        end
    }
}
