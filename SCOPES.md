# List of resources and their priveleges

## Games

| # | Hash                         | Name                                         |
| - | ---------------------------- | -------------------------------------------- |
| 1 | `6gh4gqd5s8j5a1r8lsm3vkh72g` | [NIKKE v0.3.0](games/nikke/integration.luau) |

1. Current NIKKE integration uses "fake game installation" trick. Instead of
   handling game itself, it downloads official launcher to prepared wine prefix
   and asks user to perform game installation through the launcher. Thus it
   requires `process_api` to run the official installer.

## Packages

| # | Hash                         | Name                                                           |
| - | ---------------------------- | -------------------------------------------------------------- |
| 1 | `436jznvxxrw1hxlh0y8wrlf9aa` | [components/wine v0.1.3](packages/components/wine.luau)        |
| 2 | `35wzr0zrac7pkrjcax27chjbxw` | [umu-launcher v0.2.2](packages/umu-launcher/umu-launcher.luau) |
| 3 | `0iwgnv2bh5fw6ssacwmxmnws6v` | [sophon-tools v0.2.4](packages/sophon-tools/sophon-tools.luau) |
| 4 | `5azxviib25ybq376nqmg0y2wc7` | [sophon-tools v0.2.5](packages/sophon-tools/sophon-tools.luau) |

1. `components/wine` requires `process_api` to run downloaded wine binary
   to create wine prefix (`wine wineboot -u`).
2. umu-launcher bindings library requires `process_api` to run `wineboot -u`
   command using `umu-run` binary to create proton prefix. The binary is
   verified every time before execution using the `verifier` library.
3. sophon-tools bindings library requires `process_api` to operate external
   `sophon-tools` CLI tool. The binary is verified every time before execution
   using the `verifier` library.
