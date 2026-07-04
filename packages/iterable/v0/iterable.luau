-- iterable v1.4.0
-- Copyright (C) 2024 - 2025 Nikita Podvirnyi <krypt0nn@dawn.wine>
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

type Item<T> = {
    key: any,
    value: T
}

type Iterable<T> = {
    cloned: () -> Iterable<T>,
    next: () -> Item<T>?,
    first: () -> T?,
    last: () -> T?,
    map: <F>((T) -> F) -> Iterable<F>,
    filter: ((T) -> boolean) -> Iterable<T>,
    for_each: ((Item<T>) -> ()) -> Iterable<T>,
    fold: <F>(F, (F, T) -> F) -> F,
    position: ((Item<T>) -> boolean) -> Item<T>?,
    find: ((T) -> boolean) -> T?,
    any: ((T) -> boolean) -> boolean,
    chain: (Iterable<T> | {T}) -> Iterable<T>,
    flatten: <F>() -> Iterable<F>,
    partition: ((T) -> boolean) -> (Iterable<T>, Iterable<T>),
    select: ((T, T) -> boolean) -> Item<T>?,
    count: () -> number,
    min: () -> Item<T>?,
    max: () -> Item<T>?,
    sum: () -> T,
    skip: (n: number) -> Iterable<T>,
    take: (len: number) -> Iterable<T>,
    collect: () -> {T}
}

local function iter<T>(table: { T }): Iterable<T>
    -- local a = { 1, 2, 3 }
    -- print(iter(a).cloned().sum() == iter(a).sum())
    local function cloned(): Iterable<T>
        return iter(clone(table))
    end

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

    -- print(iter({ 1, 2, 3 }).first() == 1)
    local function first(): T?
        local item = next()

        if not item then
            return nil
        else
            return item.value
        end
    end

    -- print(iter({ 1, 2, 3 }).last() == 3)
    local function last(): T?
        local item = next()

        while item do
            local next_item = next()

            if not next_item then
                return item.value
            end

            item = next_item
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
    local function filter(filter: (T) -> boolean): Iterable<T>
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

    -- iter({ 1, 2, 3 }).for_each(function(item) print(item.value) end)
    local function for_each(callback: (Item<T>) -> ()): Iterable<T>
        local item = next()

        while item do
            callback(item)

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

    -- print(iter({ 1, 2, 3 }).position(function(item) return item.value == 2 end).key == 2)
    local function position(comparator: (Item<T>) -> boolean): Item<T>?
        local item = next()

        while item do
            if comparator(item) then
                return item
            end

            item = next()
        end

        return nil
    end

    -- print(iter({ 1, 2, 3 }).find(function(num) return num == 2 end).value == 2)
    local function find(comparator: (T) -> boolean): T?
        local item = next()

        while item do
            if comparator(item.value) then
                return item.value
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
    local function chain(iterator: Iterable<T> | { T }): Iterable<T>
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

    -- print(iter({ 1, { 2, 3 }, 4, 5 }).flatten().count() == 5)
    local function flatten<F>(): Iterable<F>
        local new_table = {}
        local flatten_tables = {}

        local item = next()

        while item do
            if type(item.value) == "table" then
                flatten_tables[item.key] = item.value
            else
                new_table[item.key] = item.value
            end

            item = next()
        end

        table = new_table

        for _, flatten_table in pairs(flatten_tables) do
            chain(flatten_table)
        end

        return iter(new_table)
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

    -- print(iter({ 1, 2, 3 }).skip(2).sum() == 3)
    local function skip(n: number): Iterable<T>
        while n > 0 do
            next()

            n = n - 1
        end

        return iter(table)
    end

    -- print(iter({ 1, 2, 3 }).take(2).sum() == 3)
    local function take(len: number): Iterable<T>
        local new_table = {}

        while len > 0 do
            local item = next()

            if not item then
                break
            end

            new_table[item.key] = item.value

            len = len - 1
        end

        return iter(new_table)
    end

    -- local table = { 1, 2, 3 }
    -- print(iter(table).collect() == table)
    local function collect(): {T}
        return table
    end

    local iterator = {
        cloned = cloned,
        next = next,
        first = first,
        last = last,
        map = map,
        filter = filter,
        for_each = for_each,
        fold = fold,
        position = position,
        find = find,
        any = any,
        chain = chain,
        flatten = flatten,
        partition = partition,
        select = select,
        count = count,
        min = min,
        max = max,
        sum = sum,
        skip = skip,
        take = take,
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

return function<T>(table: Iterable<T> | { T }): Iterable<T>
    return if not table.next then iter(table) else table
end
