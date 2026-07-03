# Verifier

Simple library to verify files size and hash with results caching using files
modification or creation time.

## Integration

Add `verifier` library to your package inputs:

```json
{
    "inputs": {
        "verifier": "https://raw.githubusercontent.com/an-anime-team/game-integrations/refs/heads/master/packages/verifier/verifier.luau"
    }
}
```

## Usage

```luau
local verifier = import("verifier")

-- Verifier returns a promise which has to be awaited.
local status = verifier({
    path = "sophon-tools",
    size = 8986512,
    hash = "blake3:zqkzsslhyq2nat6zuzfwy4spesqh2vcb4wixus43l5ukgpzgr72q===="
}):await()

if not status then
    error("invalid binary")
end
```

Licensed under MIT.
