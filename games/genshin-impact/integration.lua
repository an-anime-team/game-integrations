local game_api_cache = {}
local social_api_cache = {}

function game_api(edition)
  if game_api_cache[edition] == nil then
    local uri = {
      ["global"] = "https://sdk-os-static.hoyoverse.com/hk4e_global/mdk/launcher/api/resource?key=gcStgarh&launcher_id=10",
      ["china"]  = "https://sdk-os-static.hoyoverse.com/hk4e_global/mdk/launcher/api/resource?key=gcStgarh&launcher_id=10"
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
  local uri = {
    ["global"] = "card.jpg",
    ["china"]  = "card-china.jpg"
  }

  return uri[edition]
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

-- Get installed game version
function v1_game_get_version(path, edition)
  local manager_path = {
    ["global"] = path .. "/GenshinImpact_Data/globalgamemanagers",
    ["china"]  = path .. "/YuanShen_Data/globalgamemanagers"
  }

  local manager_file = io.open(manager_path[edition], "rb")

  if not manager_file then
    return nil
  end

  manager_file:seek("set", 4000)

  return manager_file:read(10000):gmatch("[1-9]+[.][0-9]+[.][0-9]+")()
end

-- Get full game downloading info
function v1_game_get_download(edition)
  local latest_info = game_api(edition)["data"]["game"]["latest"]
  local segments = {}
  local size = 0

  for _, segment in pairs(latest_info["segments"]) do
    table.insert(segments, segment["path"])

    size = size + segment["package_size"]
  end

  return {
    ["version"] = latest_info["version"],
    ["edition"] = edition,
  
    ["download"] = {
      ["type"]     = "segments",
      ["size"]     = size,
      ["segments"] = segments
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
    local segments = {}
    local size = 0

    for _, segment in pairs(latest_info["segments"]) do
      -- table.insert(segments, {
      --   ["uri"]  = segment["path"],
      --   ["size"] = segment["package_size"],
      --   ["md5"]  = segment["md5"]
      -- })

      table.insert(segments, segment["path"])

      size = size + segment["package_size"]
    end

    return {
      ["current_version"] = version,
      ["latest_version"]  = latest_info["version"],

      ["edition"] = edition,
      ["status"]  = "outdated",

      ["diff"] = {
        ["type"]     = "segments",
        ["size"]     = size,
        ["segments"] = segments
      }
    }
  end
end

-- Get game launching options
function v1_game_get_launch_options(path, edition)
  local executable = {
    ["global"] = "GenshinImpact.exe",
    ["china"]  = "YuanShen.exe"
  }

  return {
    ["executable"]  = executable[edition],
    ["environment"] = {}
  }
end

function get_voiceover_title(language)
  local names = {
    ["en-us"] = "English",
    ["ja-jp"] = "Japanese",
    ["ko-kr"] = "Korean",
    ["zh-cn"] = "Chinese"
  }

  if names[language] ~= nil then
    return names[language]
  else
    return language
  end
end

-- Get list of game addons (voice packages)
function v1_addons_get_list(edition)
  local latest_info = game_api(edition)["data"]["game"]["latest"]
  local voiceovers = {}

  for _, package in pairs(latest_info["voice_packs"]) do
    table.insert(voiceovers, {
      ["type"]     = "module",
      ["name"]     = package["language"],
      ["title"]    = get_voiceover_title(package["language"]),
      ["version"]  = latest_info["version"],
      ["required"] = false
    })
  end

  return {
    {
      ["name"]   = "voiceovers",
      ["title"]  = "Voiceovers",
      ["addons"] = voiceovers
    }
  }
end

-- Get full addon downloading info
function v1_addons_get_download(group_name, addon_name, edition)
  local latest_info = game_api(edition)["data"]["game"]["latest"]
  local results = {}

  for _, package in pairs(latest_info["voice_packs"]) do
    results["voiceovers." .. package["language"]] = {
      ["version"] = latest_info["version"],
      ["edition"] = edition,
      ["download"] = {
        ["type"] = "archive",
        ["size"] = package["size"],
        ["uri"]  = package["path"]
      }
    }
  end

  return results[group_name .. "." .. dlc_name]
end

-- -- Get dlc version diff
-- function v1_dlc_get_diff(group_name, dlc_name, path, edition)
--   local installed_info = v1_game_get_info(path)

--   if installed_info == nil then
--     return nil
--   else
--     local latest_info = game_api(installed_info["edition"])["data"]["game"]["latest"]

--     -- It should be impossible to have higher installed version
--     -- but just in case I have to cover this case as well
--     if installed_info["version"] >= latest_info["version"] then
--       return {
--         ["current_version"] = installed_info["version"],
--         ["latest_version"]  = latest_info["version"],

--         ["edition"] = installed_info["edition"],
--         ["status"]  = "latest"
--       }
--     elseif installed_info["version"] < latest_info["version"] then
--       local segments = {}
--       local size = 0

--       for _, segment in pairs(latest_info["segments"]) do
--         -- table.insert(segments, {
--         --   ["uri"]  = segment["path"],
--         --   ["size"] = segment["package_size"],
--         --   ["md5"]  = segment["md5"]
--         -- })

--         table.insert(segments, segment["path"])

--         size = size + segment["package_size"]
--       end

--       return {
--         ["current_version"] = installed_info["version"],
--         ["latest_version"]  = latest_info["version"],

--         ["edition"] = installed_info["edition"],
--         ["status"]  = "outdated",

--         ["diff"] = {
--           ["type"]     = "segments",
--           ["size"]     = size,
--           ["segments"] = segments
--         }
--       }
--     end
--   end
-- end
