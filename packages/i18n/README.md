# i18n v1.0.1

Centralized place for common strings localization. Recommended to be used by
other packages to allow remote translation updates.

Feel free to open PR to add your language or new strings for translation.

Please do not use machine translations here.

## Integration

Add `i18n` package to your integration package inputs:

```json
{
    "standard": 1,
    "inputs": {
        "i18n": "https://raw.githubusercontent.com/an-anime-team/game-integrations/refs/heads/rewrite/packages/i18n/package.json"
    }
}
```

Import the package in your integration module:

```lua
-- Import the i18n library
local i18n = import("i18n").i18n
```

Provide `LoclizableString` translations for strings from the `locales.toml` file:

```lua
return {
    -- Simple translation
    title = i18n("download") or "Download",

    -- Translation with options
    format = function(curr, total, diff)
        return i18n("downloading_progress", {
            current = curr / 1000 / 1000,
            total = total / 1000 / 1000
        })
    end
}
```

Module and translations are licensed under [GPL-3.0](../../LICENSE).
