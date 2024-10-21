# Iterable v1.0.0

Advanced iterators syntax implementation for luau.

## Integration

Add iterable module to your package inputs:

```json
{
    "inputs": {
        "iterable": "https://raw.githubusercontent.com/an-anime-team/game-integrations/refs/heads/rewrite/packages/iterable/iterable.lua"
    }
}
```

Import the module:

```lua
-- Import the iterable library
local iter = import("iterable")
```

## Usage

```lua
type Item<T> = { key = any, value = T }
type Iterable<T> = { next: () -> Item<T>?, ... }
```

### Iterator in loops

Iterables implement special `__iter` metamethod to work inside of for loops.

```lua
local iter = import("iterable")

-- [a] = 1
-- [b] = 2
-- [c] = 3
for k, v in iter({ a = 1, b = 2, c = 3 }) do
	print(`[{k}] = {v}`)
end
```

### `next(): Item<T>`

Try to poll the next iterator item, returning nil when no more items stored.

```lua
local iter = import("iterable")

local items = iter({
    "Hello",
    "World",
    a = 1,
    b = 2,
    c = 3
})

local item = items.next()

-- [1] = Hello
-- [2] = World
-- [a] = 1
-- [c] = 3
-- [b] = 2
while item do
    print(`[{item.key}] = {item.value}`)

    item = items.next()
end
```

### `map(<F>(T) -> F): Iterable<F>`

Apply given function to all the iterator items, returning updated iterator.

```lua
local iter = import("iterable")

-- { 1, 4, 9 }
local items = iter({ 1, 2, 3 }).map(function(num) return num * num end)

for _, num in items do
    print(num)
end
```

### `filter((T) -> boolean): Iterable<T>`

Use given function to choose what items to keep in the iterator.

```lua
local iter = import("iterable")

-- { 2, 4 }
for _, num in iter({ 1, 2, 3, 4 ,5 }).filter(function(num) return num % 2 == 0 end) do
    print(num)
end
```

### `for_each((T) -> ()): Iterable<T>`

Execute given callback on each iterator item and return the iterator without changes.

```lua
local iter = import("iterable")

iter({ 1, 2, 3 })
    .for_each(function(num) print(`before: {num}`) end) -- { 1, 2, 3 }
    .filter(function(num) return num % 2 == 1)
    .for_each(function(num) print(`after: {num}`) end) -- { 1, 3 }
```

### `fold<F>(F, (F, T) -> F): F`

Accumulate all the iterator items into a single one.

```lua
local iter = import("iterable")

local greeting = iter({ "Hello", " ", "World" })
    .fold("", function(acc, word) return acc .. word end)

-- "Hello World"
print(greeting)
```

### `find((T) -> boolean): Item<T>?`

Try to find iterator item using provided search function.

```lua
local iter = import("iterable")

local item = iter({ 1, 2, 3 }).find(function(num) return num % 2 == 0 end)

print(item.key)   -- 2
print(item.value) -- 2
```

### `any((T) -> boolean): boolean`

Return true if there's at least one item in the iterator accepted
by the provided function.

```lua
local iter = import("iterable")

local has_even = iter({ 1, 2, 3 }).any(function(num) return num % 2 == 0 end)

-- true
print(has_even)
```

### `chain(Iterable<T> | table): Iterable<T>`

Chain two iterators together.

> This function respects iterators keys. If key has type `number` - then
> it will be pushed to the end of the first iterator. Otherwise it will be
> inserted into the first iterator under this key, overwriting its value
> if there already was one.

```lua
local iter = import("iterable")

-- [1] = 3
-- [2] = 4
-- [3] = 7
-- [a] = 1
-- [c] = 6
-- [b] = 5
for k, v in iter({ a = 1, b = 2, 3, 4 }).chain({ b = 5, c = 6, 7 }) do
    print(`[{k}] = {v}`)
end
```

### `partition((T) -> boolean): (Iterable<T>, Iterable<T>)`

Split an iterator into two using a comparison function.

```lua
local iter = import("iterable")

local numbers = iter({ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10 })

local even, odd = numbers.partition(function(num) return num % 2 == 0 end)

print("even:")

-- { 2, 4, 6, 8, 10 }
for _, num in even do
    print(num)
end

print("odd")

-- { 1, 3, 5, 7, 9 }
for _, num in odd do
    print(num)
end
```

### `select((T, T) -> boolean): Item<T>?`

Select some iterator item using provided comparison function.

```lua
local iter = import("iterable")

local selected = iter({ 1, 2, 3, 4, 5, 6, 7 })
    .select(function(a, b) return a * a < b end)

-- 5
print(selected.value)
```

### `count(): number`

Calculate amount of items in the iterator.

```lua
local iter = import("iterable")

local count = iter({ a = 1, b = 2, c = 3, 4, 5, 6 }).count()

-- 6
print(count)
```

### `min(): Item<T>?`

Get minimal item in the iterator.

```lua
local iter = import("iterable")

local min = iter({ a = 1, b = 2, c = 3, 4, 5, 6 }).min()

-- 1
print(min)
```

### `max(): Item<T>?`

Get maximal item in the iterator.

```lua
local iter = import("iterable")

local max = iter({ a = 1, b = 2, c = 3, 4, 5, 6 }).max()

-- 6
print(max)
```

### `sum(): T?`

Sum all the items in the iterator.

```lua
local iter = import("iterable")

local sum = iter({ a = 1, b = 2, c = 3, 4, 5, 6 }).sum()

-- 21
print(sum)
```

### `collect(): {T}`

Convert iterator back to a lua table.

```lua
local iter = import("iterable")

local items = { a = 1, b = 2, c = 3, 4, 5, 6 }

-- true
print(iter(items).collect() == items)
```

Licensed under [GPL-3.0](../../LICENSE).
