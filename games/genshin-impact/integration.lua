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
    ["global"] = "/var/home/observer/projects/new-anime-core/anime-games-launcher/assets/images/games/genshin/card.jpg",
    ["china"]  = "/var/home/observer/projects/new-anime-core/anime-games-launcher/assets/images/games/genshin/card-china.jpg"
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
function v1_game_is_installed(game_path)
  return io.open(game_path .. "/UnityPlayer.dll", "rb") ~= nil
end

-- Get installed game version
function v1_game_get_version(game_path, edition)
  local manager_path = {
    ["global"] = game_path .. "/GenshinImpact_Data/globalgamemanagers",
    ["china"]  = game_path .. "/YuanShen_Data/globalgamemanagers"
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
function v1_game_get_diff(game_path, edition)
  local installed_version = v1_game_get_version(game_path, edition)

  if not installed_version then
    return nil
  end

  local game_data = game_api(edition)["data"]["game"]

  local latest_info = game_data["latest"]
  local diffs = game_data["diffs"]

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
  else
    for _, diff in pairs(diffs) do
      if diff["version"] == installed_version then
        return {
          ["current_version"] = installed_version,
          ["latest_version"]  = latest_info["version"],

          ["edition"] = edition,
          ["status"]  = "outdated",

          ["diff"] = {
            ["type"] = "archive",
            ["size"] = diff["package_size"],
            ["uri"]  = diff["path"]
          }
        }
      end
    end

    return {
      ["current_version"] = installed_version,
      ["latest_version"]  = latest_info["version"],

      ["edition"] = edition,
      ["status"]  = "unavailable"
    }
  end
end

-- Get game launching options
function v1_game_get_launch_options(game_path, edition)
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

-- Check if addon is installed
function v1_addons_is_installed(group_name, addon_name, addon_path, edition)
  if group_name == "voiceovers" then
    return io.open(addon_path .. "/1001.pck", "rb") ~= nil
  end

  return false
end

-- Get installed addon version
function v1_addons_get_version(group_name, addon_name, addon_path, edition)
  local version = io.open(addon_path .. "/.version", "rb")

  if version == nil then
    return nil
  end

  local version = version:read(3)

  local major = string.byte(version:sub(1, 1))
  local minor = string.byte(version:sub(2, 2))
  local patch = string.byte(version:sub(3, 3))

  return major .. "." .. minor .. "." .. patch
end

-- Get full addon downloading info
function v1_addons_get_download(group_name, addon_name, edition)
  local latest_info = game_api(edition)["data"]["game"]["latest"]

  if group_name == "voiceovers" then
    for _, package in pairs(latest_info["voice_packs"]) do
      if package["language"] == addon_name then
        return {
          ["version"] = latest_info["version"],
          ["edition"] = edition,

          ["download"] = {
            ["type"] = "archive",
            ["size"] = package["size"],
            ["uri"]  = package["path"]
          }
        }
      end
    end
  end

  return nil
end

-- Get addon version diff
function v1_addons_get_diff(group_name, addon_name, addon_path, edition)
  local installed_version = v1_addons_get_version(group_name, addon_name, addon_path, edition)

  if installed_version ~= nil then
    local game_data = game_api(edition)["data"]["game"]

    local latest_info = game_data["latest"]
    local diffs = game_data["diffs"]

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
    else
      if group_name == "voiceovers" then
        for _, diff in pairs(diffs) do
          if diff["version"] == installed_version then
            for _, package in pairs(diff["voice_packs"]) do
              if package["language"] == addon_name then
                return {
                  ["current_version"] = installed_version,
                  ["latest_version"]  = latest_info["version"],

                  ["edition"] = edition,
                  ["status"]  = "outdated",

                  ["diff"] = {
                    ["type"] = "archive",
                    ["size"] = package["package_size"],
                    ["uri"]  = package["path"]
                  }
                }
              end
            end

            return nil
          end
        end

        return {
          ["current_version"] = installed_version,
          ["latest_version"]  = latest_info["version"],

          ["edition"] = edition,
          ["status"]  = "unavailable"
        }
      end
    end
  end

  return nil
end
