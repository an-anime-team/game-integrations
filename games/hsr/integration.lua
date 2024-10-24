return {
    standard = 1,

    editions = function()
        local hyvlib = import("hyvlib").hyvlib

        local editions = {}

        for name, edition in pairs(hyvlib.hsr) do
            table.insert(editions, {
                name = name,
                title = edition.title
            })
        end

        return editions
    end,

    components = function()
        return {}
    end,

    game = {
        get_status = function(edition: string)
            return "installed"
        end,

        get_diff = function(edition: string)
            return nil
        end,

        get_launch_info = function(edition: string)
            local hyvlib = import("hyvlib").hyvlib

            dbg(hyvlib)
            dbg(hyvlib.hsr.global.api.get())

            return {
                status = "disabled",
                hint = {
                    en = "It's a test implementation not meant for real use",
                    ru = "Это тестовая реализация, не предназначенная для реального использования"
                },
                binary = ""
            }
        end
    }
}
