# i18n

A very simple text localization library.

A localizations file is a simple TOML file with the following syntax:

```toml
[my_string_key]
en = "My string key"
ru = "Ключ моей строки"
zh-cn = "..."
```

Each string has a key, which is a toml table name. Within this table, keys are
language names in the standard `language-country` or just `language` format
(2 letters each), and values are translations of this string for this language.

The library provides translations for many standard strings, and it's
recommended to re-use them or, if your string is pretty generic, make a PR to
add it to the library instead of making your own localizations file. With this,
translators could edit your strings from this single repository in future.

Please do not use machine translations here.

## Integration

Add `i18n` package to your integration package inputs:

```json
{
    "inputs": {
        "i18n": "https://raw.githubusercontent.com/an-anime-team/game-integrations/refs/heads/rewrite/packages/i18n/package.json"
    }
}
```

Import the package in your integration module:

```lua
-- Import the i18n library
local i18n = load("i18n").value.i18n.value()

-- Import the i18n library with custom translations
local i18n = load("i18n").value.i18n.value(
    -- imported locale files
    load("my_locales_1").value,
    load("my_locales_2").value
)
```

Provide `LoclizableString` translations for strings from the `locales.toml` file:

```lua
return {
    -- Simple translation
    title = i18n("download"),

    -- Translation with options
    format = function(curr, total, diff)
        return i18n("downloading_progress_mb", {
            current = curr / 1000 / 1000,
            total = total / 1000 / 1000
        })
    end
}
```

Module and translations are licensed under [GPL-3.0-or-later](../../LICENSE).
