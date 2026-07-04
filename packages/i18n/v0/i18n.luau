-- i18n v2.0.0
-- Copyright (C) 2025 - 2026 Nikita Podvirnyi <krypt0nn@dawn.wine>
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

-- { key: { lang: value } }
type LocalesMap = { [string]: { [string]: string } };

local locales_cache = {}

-- Load provided locale files or tables and return resulting object.
return function(...: string | LocalesMap): (string, { [string]: string } | nil) -> { [string]: string } | string | nil
    local locales: LocalesMap = {}

    local function add_locales(new_locales: LocalesMap)
        for key, langs in pairs(new_locales) do
            if typeof(langs) ~= "table" then
                continue
            end

            if not locales[key] then
                locales[key] = {}
            end

            for lang, value in pairs(langs) do
                if typeof(value) ~= "string" then
                    continue
                end

                locales[key][lang] = value
            end
        end
    end

    local groups = {
        "interface",
        "progress",
        "game",
        "components"
    }

    for _, key in ipairs(groups) do
        if not locales_cache[key] then
            local locales_path = load(key)

            if locales_path.value and fs.exists(locales_path.value) then
                local loaded_locales = fs.read_file(locales_path.value):await()

                locales_cache[key] = str.decode("toml", str.from_bytes(loaded_locales))
            end
        end

        if locales_cache[key] then
            add_locales(locales_cache[key])
        end
    end

    for _, input in ipairs({ ... }) do
        if typeof(input) == "string" then
            local loaded_locales = fs.read_file(input):await()

            loaded_locales = str.decode("toml", str.from_bytes(loaded_locales))

            add_locales(loaded_locales)
        elseif typeof(input) == "table" then
            add_locales(input :: LocalesMap)
        end
    end

    return function(key: string, options: { [string]: string } | nil): { [string]: string } | string | nil
        local values = clone(locales[key])

        if not options or not values then
            return values or key
        end

        for lang, value in pairs(values) do
            for opt_key, opt_value in pairs(options) do
                value = value:gsub(`\{{opt_key}\}`, opt_value)
            end

            values[lang] = value
        end

        return values
    end
end
