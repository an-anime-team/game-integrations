local api_url = "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getGamePackages?launcher_id=VYTpXlbWo8"

local api_cache = nil

return {
    api = {
        -- hyvlib.api.fetch()
        -- Try to fetch the HYVse API
        fetch = function()
            if not api_cache then
                local response = net.fetch(api_url)

                if not response.is_ok then
                    error("API request failed: HTTP code " .. response.status)
                end

                api_cache = str.decode(str.from_bytes(response.body), "json")
            end

            return api_cache
        end
    }
}
