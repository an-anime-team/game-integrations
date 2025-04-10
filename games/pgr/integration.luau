type Variant = {
    platform: string,
    edition: string
}

type Version = {
    version: string,
    title: string,
    url: string
}

return {
    standard = 1,

    editions = function(platform: string)
        return {
            {
                name = "global",
                title = {
                    en = "Global",
                    ru = "Глобальная",
                    fr = "Global"
                }
            }
        }
    end,

    game = {
        get_status = function(variant: Variant)
            return "installed"
        end,

        get_diff = function(variant: Variant)
            return nil
        end,

        get_launch_info = function(variant: Variant)
            return {
                status = "disabled",
                hint = {
                    en = "WIP implementation used for testing",
                    ru = "Это тестовая реализация, не предназначенная для реального использования",
                    ru = "WIP implémentation utilisée pour faire des tests"
                },
                binary = ""
            }
        end
    },

    settings = {
        get_property = function(name: string)
            return nil
        end,

        set_property = function(name: string, value: any) end,

        get_layout = function(variant: Variant)
            return {}
        end
    }
}
