-- ZZZ integration v0.1.0
-- Copyright (C) 2026  Nikita Podvirnyi <krypt0nn@vk.com>
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

type GameVariant = {
    platform: string,
    edition: string
}

----------------------------- translations -----------------------------

local __i18n = nil

local function i18n(...)
    if not __i18n then
        local locales = import("locales-src")

        locales = fs.read_file(locales):await()
        locales = str.decode("toml", str.from_bytes(locales))

        __i18n = import("i18n").i18n(locales)
    end

    return (__i18n)(...)
end

----------------------------- settings -----------------------------

local __settings = nil

local function get_settings_layout()
    if not __settings then
        __settings = import("settings")({
            game = "zenless_zone_zero",
            layout = {}
        })
    end

    return __settings
end

----------------------------- integration -----------------------------

return function()
    local iter = import("iterable")

    local settings = get_settings_layout()

    local lua_proton = import("lua-proton").proton({
        umu_launcher = {
            game_id = "umu-zenlesszonezero"
        },

        prefix = {
            name = "zenless_zone_zero"
        },

        settings = {
            get_property = settings.get_property,
            set_property = settings.set_property
        }
    })

    return {
        game = {
            get_launch_info = function(variant: GameVariant)
                return nil
            end,

            get_actions_pipeline = function(variant: GameVariant)
                return lua_proton.game.get_actions_pipeline(variant)
            end
        },

        settings = {
            get_layout = function(variant: GameVariant)
                return iter({})
                    .chain(settings.get_layout(variant))
                    .chain(lua_proton.settings.get_layout(variant))
                    .collect()
            end,

            get_property = function(name: string): any
                return settings.get_property(name)
            end,

            set_property = function(name: string, value: any)
                settings.set_property(name, value)
            end
        }
    }
end
