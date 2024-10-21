-- iterable v1.0.0
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

type Item<T> = {
    key: any,
    value: T
}

type Iterable<T> = {
    next: () -> Item<T>?,
    map: <F>((T) -> F) -> Iterator<F>,
    filter: ((T) -> boolean) -> Iterator<T>,
    for_each: ((T) -> ()) -> Iterator<T>,
    fold: <F>(F, (F, T) -> F) -> F,
    find: ((T) -> boolean) -> Item<T>?,
    any: ((T) -> boolean) -> boolean,
    chain: (Iterable<T> | table) -> Iterable<T>,
    partition: ((T) -> boolean) -> (Iterable<T>, Iterable<T>),
    select: ((T, T) -> boolean) -> Item<T>?,
    count: () -> number,
    min: () -> Item<T>?,
    max: () -> Item<T>?,
    sum: () -> T?,
    collect: () -> {T}
}

local function iter<T>(table: {T}): Iterable<table>
    -- print(iter({ 1 }).next().value == 1)
    local function next(): Item<T>?
        for k, v in ipairs(table) do
            table[k] = nil

            return {
                key = k,
                value = v
            }
        end

        for k, v in pairs(table) do
            table[k] = nil

            return {
                key = k,
                value = v
            }
        end

        return nil
    end

    -- print(iter({ 5 }).map(function(num) return num * num end).next().value == 25)
    local function map<F>(transformer: (T) -> F): Iterable<F>
        local transformed = {}
        local item = next()

        while item do
            transformed[item.key] = transformer(item.value)

            item = next()
        end

        return iter(transformed)
    end

    -- print(iter({ 1, 2, 3 }).filter(function(num) return num % 2 == 1 end).count() == 2)
    local function filter(filter: (T) -> boolean): Iterator<T>
        local filtered = {}
        local item = next()

        while item do
            if filter(item.value) then
                filtered[item.key] = item.value
            end

            item = next()
        end

        return iter(filtered)
    end

    -- iter({ 1, 2, 3 }).for_each(function(num) print(num) end)
    local function for_each(callback: (T) -> ()): Iterator<T>
        local item = next()

        while item do
            callback(item.value)

            item = next()
        end

        return iter(table)
    end

    -- print(iter({ "Hello", "World" }).fold("", function(acc, word) return `{acc} {word}` end) == " Hello World")
    local function fold<F>(init: F, accumulator: (F, T) -> F): F
        local item = next()

        while item do
            init = accumulator(init, item.value)

            item = next()
        end

        return init
    end

    -- print(iter({ 1, 2, 3 }).find(function(num) return num == 2 end).value == 2)
    local function find(comparator: (T) -> boolean): Item<T>?
        local item = next()

        while item do
            if comparator(item.value) then
                return item
            end

            item = next()
        end

        return nil
    end

    -- print(iter({ 1, 2, 3 }).any(function(num) return num % 2 == 0 end))
    local function any(comparator: (T) -> boolean): boolean
        return find(comparator) ~= nil
    end

    -- This method uses keys of the chaining iterator to update
    -- the original iterator.
    -- 
    -- print(iter({ 1, 2 }).chain({ 3, 4, 5 }).count() == 5)
    -- print(iter({ a = 1, b = 2 }).chain({ b = 3 }).count() == 2)
    local function chain(iterator: Iterable<T> | table): Iterable<T>
        if not iterator.next then
            iterator = iter(iterator)
        end

        local item = iterator.next()

        while item do
            if type(item.key) == "number" then
                table[#table + 1] = item.value
            else
                table[item.key] = item.value
            end

            item = iterator.next()
        end

        return iter(table)
    end

    -- local even, odd = iter({ 1, 2, 3, 4 }).partition(function(num) return num % 2 == 0 end)
    local function partition(comparator: (T) -> boolean): (Iterable<T>, Iterable<T>)
        local left = {}
        local right = {}

        local item = next()

        while item do
            if comparator(item.value) then
                left[item.key] = item.value
            else
                right[item.key] = item.value
            end

            item = next()
        end

        return iter(left), iter(right)
    end

    -- print(iter({ 1, 2, 3 }).select(function(a, b) return a < b end).value == 3)
    local function select(comparator: (T, T) -> boolean): Item<T>?
        local selected = next()

        if not selected then
            return nil
        end

        local item = next()

        while item do
            if comparator(selected.value, item.value) then
                selected = item
            end

            item = next()
        end

        return selected
    end

    -- print(iter({ "Hello", "World", a = 1, b = 2, c = 3 }).count() == 5)
    local function count(): number
        return fold(0, function(count, _) return count + 1 end)
    end

    -- print(iter({ 1, 2, 3 }).min().value == 1)
    local function min(): Item<T>?
        return select(function(a, b) return a > b end)
    end

    -- print(iter({ 1, 2, 3 }).max().value == 3)
    local function max(): Item<T>?
        return select(function(a, b) return a < b end)
    end

    -- print(iter({ 1, 2, 3 }).sum() == 6)
    local function sum(): T?
        local init = next()

        if not init then
            return nil
        end

        return fold(init.value, function(sum, item) return sum + item end)
    end

    -- local table = { 1, 2, 3 }
    -- print(iter(table).collect() == table)
    local function collect(): {T}
        return table
    end

    local iterator = {
        next = next,
        map = map,
        filter = filter,
        for_each = for_each,
        fold = fold,
        find = find,
        any = any,
        chain = chain,
        partition = partition,
        select = select,
        count = count,
        min = min,
        max = max,
        sum = sum,
        collect = collect
    }

    setmetatable(iterator, {
        __iter = function(iter)
            local function next<T>(iter: Iterable<T>)
                local item = iter.next()

                if not item then
                    return nil
                end

                return item.key, item.value
            end

            return next, iter
        end
    })

    return iterator
end

return function<T>(table: Iterable<T> | {T}): Iterable<T>
    return if not table.next then iter(table) else table
end
