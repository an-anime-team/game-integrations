-- import v0.1.0
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

--!nocheck

local working = true

if not load then
    dbg("`load` function is not available")

    working = false
end

local function read_value(value)
    if not value.format then
        return value
    elseif value.format == "package" then
        local outputs = {}

        for name, output in pairs(value.value) do
            -- TODO: metatable with read_value call to prevent infinite loop on cycles
            outputs[name] = output.value
        end

        return outputs
    else
        return value.value
    end
end

return function(...)
    if not working then
        return nil
    end

    local results = {}

    -- TODO: support loading package's outputs as import("package_name/output_name")
    for _, name in ipairs(table.pack(...)) do
        local value = load(name)

        table.insert(results, read_value(value))
    end

    return table.unpack(results)
end
