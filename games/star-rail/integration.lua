local game_api_cache = {}
local social_api_cache = {}

function game_api(edition)
  if game_api_cache[edition] == nil then
    local uri = {
      ["global"] = "https://hkrpg-launcher-static.hoyoverse.com/hkrpg_global/mdk/launcher/api/resource?channel_id=1&key=vplOVX8Vn7cwG8yb&launcher_id=35",
      ["china"]  = "https://hkrpg-launcher-static.hoyoverse.com/hkrpg_global/mdk/launcher/api/resource?channel_id=1&key=vplOVX8Vn7cwG8yb&launcher_id=35"
    }

    game_api_cache[edition] = v1_json_decode(v1_network_http_get(uri[edition]))
  end

  return game_api_cache[edition]
end

function social_api(edition)
  if social_api_cache[edition] == nil then
    local uri = {
      ["global"] = "https://hkrpg-launcher-static.hoyoverse.com/hkrpg_global/mdk/launcher/api/content?filter_adv=true&key=vplOVX8Vn7cwG8yb&launcher_id=35&language=en-us",
      ["china"]  = "https://hkrpg-launcher-static.hoyoverse.com/hkrpg_global/mdk/launcher/api/content?filter_adv=true&key=vplOVX8Vn7cwG8yb&launcher_id=35&language=en-us"
    }

    social_api_cache[edition] = v1_json_decode(v1_network_http_get(uri[edition]))
  end

  return social_api_cache[edition]
end

-- Get card picture URI
function v1_visual_get_card_picture(edition)
  return "/var/home/observer/projects/new-anime-core/anime-games-launcher/assets/images/games/star-rail/card.jpg"
end

-- Get background picture URI
function v1_visual_get_background_picture(edition)
  return social_api(edition)["data"]["adv"]["background"]
end

-- Get list of game editions
function v1_game_get_editions_list()
  return {
    {
      ["name"]  = "global",
      ["title"] = "Global"
    },
    {
      ["name"]  = "china",
      ["title"] = "China"
    }
  }
end

-- Check if the game is installed
function v1_game_is_installed(path)
  local file = io.open(path .. "/UnityPlayer.dll", "rb")

  return file ~= nil
end

-- Get installed game info
function v1_game_get_version(path, edition)
  local manager_path = path .. "/StarRail_Data/data.unity3d"
  local manager_file = io.open(manager_path, "rb")
  if not manager_file then
    return nil
  end

  manager_file:seek("set", 4000)
  return manager_file:read(10000):gmatch("[1-9]+[.][0-9]+[.][0-9]+")()
end

-- Get full game downloading info
function v1_game_get_download(edition)
  local latest_info = game_api(edition)["data"]["game"]["latest"]

  return {
    ["version"] = latest_info["version"],
    ["edition"] = edition,
    ["download"] = {
      ["type"] = "archive",
      ["size"] = latest_info["package_size"],
      ["uri"]  = latest_info["path"]
    }
  }
end

-- Get game version diff
function v1_game_get_diff(path, edition)
  local version = v1_game_get_version(path, edition)
  if not version then
    return nil
  end

  local latest_info = game_api(edition)["data"]["game"]["latest"]

  -- FIXME: comparing versions like that will not work

  -- It should be impossible to have higher installed version
  -- but just in case I have to cover this case as well
  if version >= latest_info["version"] then
    return {
      ["current_version"] = version,
      ["latest_version"]  = latest_info["version"],

      ["edition"] = edition,
      ["status"]  = "latest"
    }
  elseif version < latest_info["version"] then
    return {
      ["current_version"] = version,
      ["latest_version"]  = latest_info["version"],

      ["edition"] = edition,
      ["status"]  = "outdated",

      ["diff"] = {
        ["type"] = "archive",
        ["size"] = latest_info["package_size"],
        ["uri"]  = latest_info["path"]
      }
    }
  end
end

-- Get game launching options
function v1_game_get_launch_options(path, edition)
  -- TODO: patcher

  return {
    ["executable"]  = "StarRail.exe",
    ["environment"] = {}
  }
end

-- Get list of game DLCs (voice packages)
function v1_dlc_get_list(edition)
  local voiceovers = {}

  for _, package in pairs(game_api(edition)["data"]["game"]["latest"]["voice_packs"]) do
    table.insert(voiceovers, {
      ["name"]  = package["language"],
      ["title"] = package["language"],
      ["required"] = false
    })
  end

  return {
    {
      ["name"]  = "voiceover",
      ["title"] = "Voiceover",
      ["dlcs"]  = voiceovers
    }
  }
end
