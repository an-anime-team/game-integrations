# Semver

Semver implements support for the same-called [versions format](https://semver.org).

## Integration

Add semver module to your package inputs:

```json
{
    "inputs": {
        "semver": "https://raw.githubusercontent.com/an-anime-team/game-integrations/refs/heads/rewrite/packages/semver/semver.lua"
    }
}
```

Import the module:

```lua
-- Import the semver library
local semver = import("semver")
```

## Examples

```lua
local semver = import("semver")

-- Only valid semver strings are supported:
-- major.minor.patch
local version = semver("1.2") or error("invalid version format")
```

```lua
local semver = import("semver")

local a = semver("1.2.0")
local b = semver("2.3.1")

print(a)      -- "1.2.0"
print(a + b)  -- "3.5.1"
print(b - a)  -- "1.1.1"
print(a > b)  -- false
print(a == b) -- false
print(a <= b) -- true
```

Licensed under [GPL-3.0](../../LICENSE).
