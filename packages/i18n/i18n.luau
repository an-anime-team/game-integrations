-- i18n v1.0.0
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

local locales_cache = nil

local function get_translations(name: string): table | nil
    if not locales_cache then
        local locales = fs.read_file(import("locales"))

        locales_cache = str.decode(str.from_bytes(locales), "toml")
    end

    return locales_cache[name]
end

return function(name: string, options: table | nil): string | nil
    local translations = get_translations(name)

    if not options or not translations then
        return translations
    end

    for lang, translation in pairs(translations) do
        for option, value in pairs(options) do
            translation = translation:gsub(`\{{option}\}`, value)
        end

        translations[lang] = translation
    end

    return translations
end
