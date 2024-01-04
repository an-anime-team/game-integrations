local game_api_cache = {}
local social_api_cache = {}

function game_api(edition)
  if game_api_cache[edition] == nil then
    local uri = {
      ["global"] = "https://sdk-os-static.hoyoverse.com/bh3_global/mdk/launcher/api/resource?key=gcStgarh&launcher_id=10",
      ["sea"]    = "https://sdk-os-static.hoyoverse.com/bh3_global/mdk/launcher/api/resource?launcher_id=9",
      ["china"]  = "https://bh3-launcher-static.mihoyo.com/bh3_cn/mdk/launcher/api/resource?launcher_id=4",
      ["taiwan"] = "https://sdk-os-static.hoyoverse.com/bh3_global/mdk/launcher/api/resource?launcher_id=8",
      ["korea"]  = "https://sdk-os-static.hoyoverse.com/bh3_global/mdk/launcher/api/resource?launcher_id=11",
      ["japan"]  = "https://sdk-os-static.hoyoverse.com/bh3_global/mdk/launcher/api/resource?key=ojevZ0EyIyZNCy4n&launcher_id=19"
    }

    game_api_cache[edition] = v1_json_decode(v1_network_http_get(uri[edition]))
  end

  return game_api_cache[edition]
end

function social_api(edition)
  if social_api_cache[edition] == nil then
    local uri = {
      ["global"] = "https://sdk-os-static.hoyoverse.com/bh3_global/mdk/launcher/api/content?filter_adv=true&key=gcStgarh&launcher_id=10&language=en-us",
      ["sea"]    = "https://sdk-os-static.hoyoverse.com/bh3_global/mdk/launcher/api/content?filter_adv=true&key=gcStgarh&launcher_id=10&language=en-us",
      ["china"]  = "https://bh3-launcher-static.mihoyo.com/bh3_cn/mdk/launcher/api/content?filter_adv=true&launcher_id=4&language=zh-cn",
      ["taiwan"] = "https://sdk-os-static.hoyoverse.com/bh3_global/mdk/launcher/api/content?filter_adv=true&key=gcStgarh&launcher_id=10&language=en-us",
      ["korea"]  = "https://sdk-os-static.hoyoverse.com/bh3_global/mdk/launcher/api/content?filter_adv=true&key=gcStgarh&launcher_id=10&language=en-us",
      ["japan"]  = "https://sdk-os-static.hoyoverse.com/bh3_global/mdk/launcher/api/content?filter_adv=true&key=gcStgarh&launcher_id=10&language=en-us"
    }

    social_api_cache[edition] = v1_json_decode(v1_network_http_get(uri[edition]))
  end

  return social_api_cache[edition]
end

-- Get card picture URI
function v1_visual_get_card_picture(edition)
  -- FIXME
  return "/var/home/observer/projects/new-anime-core/anime-games-launcher/assets/images/games/honkai/card.jpg"
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
      ["name"]  = "sea",
      ["title"] = "Southeast Asia"
    },
    {
      ["name"]  = "china",
      ["title"] = "China"
    },
    {
      ["name"]  = "taiwan",
      ["title"] = "TW-HK-MO" -- FIXME: ?
    },
    {
      ["name"]  = "korea",
      ["title"] = "Korea"
    },
    {
      ["name"]  = "japan",
      ["title"] = "Japan"
    }
  }
end

-- Check if the game is installed
function v1_game_is_installed(path)
  local file = io.open(path .. "/UnityPlayer.dll", "rb")

  return file ~= nil
end

-- Get installed game version
function v1_game_get_version(path)
  local manager_path = path .. "/BH3_Data/globalgamemanagers"
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
  local version = v1_game_get_version(path)
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
    ["executable"]  = "BH3.exe",
    ["environment"] = {}
  }
end

-- Get list of game DLCs (voice packages)
function v1_dlc_get_list(edition)
  return {}
end
