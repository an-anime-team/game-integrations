local game_api_cache = {}
local social_api_cache = {}

function game_api(edition)
  if not game_api_cache[edition] then
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
  if not social_api_cache[edition] then
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
function v1_game_is_installed(game_path)
  return io.open(game_path .. "/UnityPlayer.dll", "rb") ~= nil
end

-- Get installed game version
function v1_game_get_version(game_path)
  local manager_file = io.open(game_path .. "/BH3_Data/globalgamemanagers", "rb")

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
function v1_game_get_diff(game_path, edition)
  local installed_version = v1_game_get_version(game_path)
  if not installed_version then
    return nil
  end

  local latest_info = game_api(edition)["data"]["game"]["latest"]

  -- FIXME: comparing versions like that will not work

  -- It should be impossible to have higher installed version
  -- but just in case I have to cover this case as well
  if installed_version >= latest_info["version"] then
    return {
      ["current_version"] = installed_version,
      ["latest_version"]  = latest_info["version"],

      ["edition"] = edition,
      ["status"]  = "latest"
    }
  elseif installed_version < latest_info["version"] then
    return {
      ["current_version"] = installed_version,
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

-- Get list of game addons
function v1_addons_get_list(edition)
  return {}
end

-- Check if addon is installed
function v1_addons_is_installed(group_name, addon_name, addon_path, edition)
  return false
end

-- Get installed addon version
function v1_addons_get_version(group_name, addon_name, addon_path, edition)
  local version_file = io.open(addon_path .. "/.version", "rb")

  if not version_file then
    return nil
  end

  local version = version_file:read(3)

  local major = version:sub(1, 1):byte()
  local minor = version:sub(2, 2):byte()
  local patch = version:sub(3, 3):byte()

  return major .. "." .. minor .. "." .. patch
end

-- Get full addon downloading info
function v1_addons_get_download(group_name, addon_name, edition)
  return nil
end

-- Get addon version diff
function v1_addons_get_diff(group_name, addon_name, addon_path, edition)
  return nil
end