# Hyvlib

Hyvlib is a general purpose library for HYVerse games. It supports common
HYVse-specific API format, games installation, updating and patching methods,
versions parsing and more.

## Integration

Add hyvlib package to your integration package inputs:

```json
{
    "standard": 1,
    "inputs": {
        "hyvlib": "https://raw.githubusercontent.com/an-anime-team/game-integrations/refs/heads/rewrite/packages/hyvlib/package.json"
    }
}
```

Import the package in your integration module:

```lua
-- Import the hyvlib library
local hyvlib = import("hyvlib").hyvlib
```

Licensed under [GPL-3.0](../../LICENSE).
