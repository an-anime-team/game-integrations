# Verifier

Simple library to verify files size and hash with results caching using files
modification or creation time.

## Integration

Add `verifier` library to your package inputs:

```json
{
    "inputs": {
        "verifier": "http://127.0.0.1:8080/packages/verifier/v0/verifier.luau"
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
