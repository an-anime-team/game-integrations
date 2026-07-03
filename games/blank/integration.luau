-- Blank game integration. Use it for learning basics.

return {
    game = {
        get_launch_info = function(variant)
            return nil

            -- return {
            --     hint = {
            --         en = "Example launch info",
            --         ru = "Пример информации запуска"
            --     },
            --     binary = "gnome-calculator"
            -- }
        end,

        get_actions_pipeline = function(variant)
            return nil

            -- return {
            --     title = "Download game",

            --     pipeline = {
            --         {
            --             title = "Download",

            --             perform = function(updater)
            --                 -- Download the game
            --             end
            --         },

            --         {
            --             title = "Extract",

            --             perform = function(updater)
            --                 -- Extract game files
            --             end
            --         }
            --     }
            -- }
        end
    },

    settings = {
        get_property = function(name)
            -- get key-value

            return nil
        end,

        set_property = function(name, value)
            -- save key-value
        end,

        get_layout = function(variant)
            return nil

            -- return {
            --     title = "Example group",
            --     description = "Example settings group",

            --     entries = {
            --         {
            --             title = "Example switch",

            --             entry = {
            --                 format = "switch",
            --                 value = true
            --             }
            --         }
            --     }
            -- }
        end
    }
}
