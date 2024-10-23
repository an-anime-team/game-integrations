local hyvlib = import("hyvlib").hyvlib

return {
    standard = 1,

    editions = {
        {
            name = "global",
            title = {
                en = "Global",
                ru = "Глобальная"
            }
        }
    },

    components = {},

    game = {
        get_status = function(edition: string)
            return "installed"
        end,

        get_diff = function(edition: string)
            return nil
        end,

        get_launch_info = function(edition: string)
            return {
                status = "disabled",
                hint = {
                    en = str.encode(hyvlib.hsr.global.api.get(), "json"),
                    -- en = "It's a test implementation not meant for real use",
                    ru = "Это тестовая реализация, не предназначенная для реального использования"
                },
                binary = ""
            }
        end
    }
}
