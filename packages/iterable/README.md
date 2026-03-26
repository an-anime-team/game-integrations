# Iterable v1.4.0

Advanced iterators syntax implementation for luau.

## Integration

Add iterable module to your package inputs:

```json
{
    "format": 1,
    "inputs": {
        "iterable": "http://127.0.0.1:8080/packages/iterable/iterable.luau"
    }
}
```

Import the module:

```luau
-- Import the iterable library
local iter = load("iterable").value
```

## Usage

```luau
type Item<T> = { key = any, value = T }
type Iterable<T> = { next: () -> Item<T>?, ... }
```

> Note: internally iterators mutate input tables, so you likely want to
> clone them before building an iterator: use `iter(clone(your_table))`
> instead of just `iter(your_table)`. Alternatively you can use
> `iter(your_table).cloned()` method.

### Iterator in loops

Iterables implement special `__iter` metamethod to work inside of for loops.

```luau
local iter = load("iterable").value

-- [a] = 1
-- [b] = 2
-- [c] = 3
for k, v in iter({ a = 1, b = 2, c = 3 }) do
    print(`[{k}] = {v}`)
end
```

### `cloned(): Iterable<T>`

Iterators consume provided tables which, due to lua design, mutates original
table provided by the user. This method creates a copy of the iterator's table
to not to mutate the one provided by the user.

```luau
local iter = load("iterable").value

local original = { 1, 2, 3 }

print(iter(original).count()) -- 3
print(#original) -- 0, because `original` was consumed by the `count` method

local cloned = { 1, 2, 3 }

print(iter(cloned).cloned().count()) -- 3
print(#cloned) -- 3, because `cloned` made a copy of the input table
```

### `next(): Item<T>`

Try to poll the next iterator item, returning nil when no more items stored.

```luau
local iter = load("iterable").value

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

### `first(): T?`

Return first value of the iterator.

```luau
local iter = load("iterable").value

print(iter({ "Hello", "World" }).first()) -- "Hello"
```

### `last(): T?`

Return last value of the iterator.

```luau
local iter = load("iterable").value

print(iter({ "Hello", "World" }).last()) -- "World"
```

### `map(<F>(T) -> F): Iterable<F>`

Apply given function to all the iterator items, returning updated iterator.

```luau
local iter = load("iterable").value

-- { 1, 4, 9 }
local items = iter({ 1, 2, 3 }).map(function(num) return num * num end)

for _, num in items do
    print(num)
end
```

### `filter((T) -> boolean): Iterable<T>`

Use given function to choose what items to keep in the iterator.

```luau
local iter = load("iterable").value

-- { 2, 4 }
for _, num in iter({ 1, 2, 3, 4 ,5 }).filter(function(num) return num % 2 == 0 end) do
    print(num)
end
```

### `for_each((Item<T>) -> ()): Iterable<T>`

Execute given callback on each iterator item and return the iterator without changes.

```luau
local iter = load("iterable").value

iter({ 1, 2, 3 })
    .for_each(function(item) print(`before: {item.value}`) end) -- { 1, 2, 3 }
    .filter(function(num) return num % 2 == 1)
    .for_each(function(item) print(`after: {item.value}`) end) -- { 1, 3 }
```

### `fold<F>(F, (F, T) -> F): F`

Accumulate all the iterator items into a single one.

```luau
local iter = load("iterable").value

local greeting = iter({ "Hello", " ", "World" })
    .fold("", function(acc, word) return acc .. word end)

-- "Hello World"
print(greeting)
```

### `position((Item<T>) -> boolean): Item<T>?`

Try to find iterator item using provided search function.

```luau
local iter = load("iterable").value

local item = iter({ 1, 2, 3 }).position(function(item) return item.value % 2 == 0 end)

print(item.key)   -- 2
print(item.value) -- 2
```

### `find((T) -> boolean): T?`

Try to find iterator item using provided search function.
Similar to `position`, except it works with values only.

```luau
local iter = load("iterable").value

local item = iter({ 1, 2, 3 }).find(function(num) return num % 2 == 0 end)

print(item) -- 2
```

### `any((T) -> boolean): boolean`

Return true if there's at least one item in the iterator accepted
by the provided function.

```luau
local iter = load("iterable").value

local has_even = iter({ 1, 2, 3 }).any(function(num) return num % 2 == 0 end)

-- true
print(has_even)
```

### `chain(Iterable<T> | {T}): Iterable<T>`

Chain two iterators together.

> This function respects iterators keys. If key has type `number` - then
> it will be pushed to the end of the first iterator. Otherwise it will be
> inserted into the first iterator under this key, overwriting its value
> if there already was one.

```luau
local iter = load("iterable").value

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

### `flatten<F>(): Iterable<F>`

Flatten two-dimensional array into one dimension.

```luau
local iter = load("iterable").value

local matrix = {
    { 1, 2, 3 },
    { 4, 5, 6 },
    7,
    8,
    9
}

print(iter(matrix).flatten().count()) -- 9
```

### `partition((T) -> boolean): (Iterable<T>, Iterable<T>)`

Split an iterator into two using a comparison function.

```luau
local iter = load("iterable").value

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

```luau
local iter = load("iterable").value

local selected = iter({ 1, 2, 3, 4, 5, 6, 7 })
    .select(function(a, b) return a * a < b end)

-- 5
print(selected.value)
```

### `count(): number`

Calculate amount of items in the iterator.

```luau
local iter = load("iterable").value

local count = iter({ a = 1, b = 2, c = 3, 4, 5, 6 }).count()

-- 6
print(count)
```

### `min(): Item<T>?`

Get minimal item in the iterator.

```luau
local iter = load("iterable").value

local min = iter({ a = 1, b = 2, c = 3, 4, 5, 6 }).min()

-- 1
print(min)
```

### `max(): Item<T>?`

Get maximal item in the iterator.

```luau
local iter = load("iterable").value

local max = iter({ a = 1, b = 2, c = 3, 4, 5, 6 }).max()

-- 6
print(max)
```

### `sum(): T?`

Sum all the items in the iterator.

```luau
local iter = load("iterable").value

local sum = iter({ a = 1, b = 2, c = 3, 4, 5, 6 }).sum()

-- 21
print(sum)
```

### `skip(n: number): Iterable<T>`

Skip first `n` items from the iterator.

```luau
local iter = load("iterable").value

-- [3] = 3
-- [4] = 4
-- [5] = 5
for k, v in iter({ 1, 2, 3, 4, 5 }).skip(2) do
    print(`[{k}] = {v}`)
end
```

### `take(len: number): Iterable<T>`

Take first `len` items from the iterator.

```luau
local iter = load("iterable").value

-- [1] = 1
-- [2] = 2
-- [3] = 3
for k, v in iter({ 1, 2, 3, 4, 5 }).take(3) do
    print(`[{k}] = {v}`)
end

-- [2] = 2
-- [3] = 3
for k, v in iter({ 1, 2, 3, 4, 5 }).skip(1).take(2) do
    print(`[{k}] = {v}`)
end
```

### `collect(): {T}`

Convert iterator back to a lua table.

```luau
local iter = load("iterable").value

local items = { a = 1, b = 2, c = 3, 4, 5, 6 }

-- true
print(iter(items).collect() == items)
```

Licensed under [GPL-3.0-or-later](../../LICENSE).
