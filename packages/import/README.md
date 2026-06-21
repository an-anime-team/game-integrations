# import v0.1.0

A simple function to import other modules or packages using standard `load`
function.

Since latest agl-runtime versions add `import` function, it's highly recommended
to use the following polyfill instead:

```luau
if not import then
    -- polyfill: old agl-runtime versions don't have `import` function
    function import(name: string)
        local resource = load(name)

        if resource.format ~= "package" then
            return resource.value
        end

        local outputs = {}

        for name, value in pairs(resource.value) do
            outputs[name] = value.value
        end

        return outputs
    end
end
```

## Integration

Add `import` luau module to your integration package inputs:

```json
{
    "format": 1,
    "inputs": {
        "import": "http://127.0.0.1:8080/packages/import/import.luau"
    }
}
```

## Usage

Provided `import` function will resolve lua modules and packages, and load
files and folders as paths.

```luau
local import = load("import").value

local example_module, example_package = import("example_module", "example_package")
```

Or pre-define `import` function like this:

```luau
function import(...)
    return (load("import").value)(...)
end

local example_module, example_package = import("example_module", "example_package")
```

Licensed under [GPL-3.0-or-later](../../LICENSE).
