# nixos-command-wrapper v0.1.0

A very simple library that returns exactly one function to wrap a game launch
info table. The library will check if the current system is NixOS, and if it is,
then append the `steam-run` binary in front of the game launch command.

## Integration

Add `nixos-command-wrapper` package to your integration package inputs:

```json
{
    "inputs": {
        "nixos-command-wrapper": "http://127.0.0.1:8080/packages/nixos-command-wrapper/nixos-command-wrapper.luau"
    }
}
```

Licensed under MIT.
