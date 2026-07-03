# List of resources and their priveleges

> Do not forget to update both `scopes.json` and `packages/allow_list.json`.

## Games

| # | Hash            | Name                                         |
| - | --------------- | -------------------------------------------- |
| 1 | `8634jdgcmnpg6` | [NIKKE v0.3.0](games/nikke/integration.luau) |
| 2 | `v1il786cpt9oe` | [NIKKE v0.3.0](games/nikke/integration.luau) |

1. Current NIKKE integration uses "fake game installation" trick. Instead of
   handling game itself, it downloads official launcher to prepared wine prefix
   and asks user to perform game installation through the launcher. Thus it
   requires `process_api` to run the official installer.
2. The same NIKKE integration, but with updated license comment.

## Packages

| # | Hash            | Name                                                           |
| - | --------------- | -------------------------------------------------------------- |
| 1 | `i56s4ooq2iomi` | [components/wine v0.1.3](packages/components/wine.luau)        |
| 2 | `4v54vm6dsocqk` | [umu-launcher v0.1.1](packages/umu-launcher/umu-launcher.luau) |
| 2 | `22u7v512gloe0` | [umu-launcher v0.2.1](packages/umu-launcher/umu-launcher.luau) |
| 2 | `gtaoj45m6cmd0` | [umu-launcher v0.2.2](packages/umu-launcher/umu-launcher.luau) |
| 3 | `mb8907ohevv0s` | [sophon-tools v0.2.1](packages/sophon-tools/sophon-tools.luau) |
| 3 | `7adauj2snadri` | [sophon-tools v0.2.2](packages/sophon-tools/sophon-tools.luau) |
| 3 | `uhdkoemhi7mua` | [sophon-tools v0.2.3](packages/sophon-tools/sophon-tools.luau) |
| 3 | `gqaq7vn3tqqf2` | [sophon-tools v0.2.4](packages/sophon-tools/sophon-tools.luau) |

1. `components/wine.luau` requires `process_api` to run downloaded wine binary
   to create wine prefix (`wine wineboot -u`).
2. umu-launcher bindings library requires `process_api` to run `wineboot -u`
   command using `umu-run` binary to create proton prefix. The binary is
   verified every time before execution using the `verifier` library.
3. sophon-tools bindings library requires `process_api` to operate external
   `sophon-tools` CLI tool. The binary is verified every time before execution
   using the `verifier` library.
