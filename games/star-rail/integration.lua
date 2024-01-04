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
function v1_game_get_editions_list(edition)
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
function v1_game_get_info(path)
  local edition = nil
  local version = nil

  local appinfo_path = path .. "/StarRail_Data/app.info"
  local appinfo = io.lines(appinfo_path)[2]
  if not appinfo then
    return nil
  end

  local appinfo_map = {
    ["Star Rail"]     = "global",
    ["崩坏：星穹铁道"] = "china"
  }
  edition = appinfo_map[appinfo]

  local manager_path = path .. "/StarRail_Data/data.unity3d"
  local manager_file = io.open(manager_path, "rb")
  if not manager_file then
    return nil
  end

  manager_file:seek("set", 4000)
  version = manager_file:read(10000):gmatch("[1-9]+[.][0-9]+[.][0-9]+")()

  return {
    ["version"] = version,
    ["edition"] = edition
  }
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
function v1_game_get_diff(path)
  local installed_info = v1_game_get_info(path)

  if installed_info == nil then
    return nil
  else
    local latest_info = game_api(installed_info["edition"])["data"]["game"]["latest"]

    -- It should be impossible to have higher installed version
    -- but just in case I have to cover this case as well
    if installed_info["version"] >= latest_info["version"] then
      return {
        ["current_version"] = installed_info["version"],
        ["latest_version"]  = latest_info["version"],

        ["edition"] = installed_info["edition"],
        ["status"]  = "latest"
      }
    elseif installed_info["version"] < latest_info["version"] then
      return {
        ["current_version"] = installed_info["version"],
        ["latest_version"]  = latest_info["version"],

        ["edition"] = installed_info["edition"],
        ["status"]  = "outdated",

        ["diff"] = {
          ["type"] = "archive",
          ["size"] = latest_info["package_size"],
          ["uri"]  = latest_info["path"]
        }
      }
    end
  end
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
