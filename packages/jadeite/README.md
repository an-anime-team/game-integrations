# jadeite

Module for running games with the jadeite autopatcher.

## Integration

Add jadeite module to your package inputs:

```json
{
    "inputs": {
        "jadeite": "https://raw.githubusercontent.com/an-anime-team/game-integrations/refs/heads/rewrite/packages/jadeite/v0/jadeite.luau"
    }
}
```

Import the module:

```luau
-- Import the jadeite library
local jadeite = import("jadeite")
```

## Examples

Wrapping the launch command:

```luau
local jadeite = import("jadeite")

-- in your get_launch_info function

return jadeite.wrap_launch_command({
  status = "normal",
  binary = "path/to/binary"
})
```

You will want to use the `jadeite.wrap_launch_command` in conjunction with the components package (wine) to launch your game.

```luau
local jadeite = import("jadeite")

-- in your get_launch_info function

local components = import_components() -- user-defined function

return components.game.wrap_launch_info(jadeite.wrap_launch_command({
  status = "normal",
  binary = "path/to/binary"
}))
```

You can specify a version by passing it as the second argument to `jadeite.wrap_launch_command`, the latest version will be used if no version is specified.

```luau
local jadeite = import("jadeite")

-- in your get_launch_info function

return jadeite.wrap_launch_command({
  status = "normal",
  binary = "path/to/binary"
}, "v2.0.0")
```

Getting the game status of a given game:

```luau
type GameStatus = {
  status: string,
  version: string
}
```

```luau
local jadeite = import("jadeite")

local game_status = jadeite.get_game_status(game, edition)
print(game_status.status)
print(game_status.version)
```
