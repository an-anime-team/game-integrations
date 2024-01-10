local game_api_cache = {}
local social_api_cache = {}

local function game_api(edition)
  if game_api_cache[edition] == nil then
    local uri = {
      ["global"] = "https://hkrpg-launcher-static.hoyoverse.com/hkrpg_global/mdk/launcher/api/resource?channel_id=1&key=vplOVX8Vn7cwG8yb&launcher_id=35",
      ["china"]  = "https://api-launcher.mihoyo.com/hkrpg_cn/mdk/launcher/api/resource?channel_id=1&key=6KcVuOkbcqjJomjZ&launcher_id=33"
    }

    game_api_cache[edition] = v1_json_decode(v1_network_http_get(uri[edition]))
  end

  return game_api_cache[edition]
end

local function social_api(edition)
  if social_api_cache[edition] == nil then
    local uri = {
      ["global"] = "https://sdk-os-static.hoyoverse.com/hk4e_global/mdk/launcher/api/content?filter_adv=true&key=gcStgarh&launcher_id=10&language=en-us",
      ["china"]  = "https://sdk-os-static.hoyoverse.com/hk4e_global/mdk/launcher/api/content?filter_adv=true&key=gcStgarh&launcher_id=10&language=zh-cn"
    }

    social_api_cache[edition] = v1_json_decode(v1_network_http_get(uri[edition]))
  end

  return social_api_cache[edition]
end

-- Convert raw number string into table of version numbers
local function split_version(version)
  local numbers = version:gmatch("([1-9]+)%.([0-9]+)%.([0-9]+)")

  for major, minor, patch in numbers do
    return {
      ["major"] = major,
      ["minor"] = minor,
      ["patch"] = patch
    }
  end

  return nil
end

-- Compare two raw version strings
-- [ 1] if version_1 > version_2
-- [ 0] if version_1 = version_2
-- [-1] if version_1 < version_2
local function compare_versions(version_1, version_2)
  local version_1 = split_version(version_1)
  local version_2 = split_version(version_2)
  
  if version_1 == nil or version_2 == nil then
    return nil
  end

  -- Thanks, noir!
  if version_1.major > version_2.major then return  1 end
  if version_1.major < version_2.major then return -1 end

  if version_1.minor > version_2.minor then return  1 end
  if version_1.minor < version_2.minor then return -1 end

  if version_1.patch > version_2.patch then return  1 end
  if version_1.patch < version_2.patch then return -1 end

  return 0
end

local function get_voiceover_title(language)
  local names = {
    ["en-us"] = "English",
    ["ja-jp"] = "Japanese",
    ["ko-kr"] = "Korean",
    ["zh-cn"] = "Chinese"
  }

  return names[language] or language
end

local function get_voiceover_folder(language)
  local names = {
    ["en-us"] = "English",
    ["ja-jp"] = "Japanese",
    ["ko-kr"] = "Korean",
    ["zh-cn"] = "Chinese(PRC)"
  }

  return names[language] or language
end

----------------------------------------------------+-----------------------+----------------------------------------------------
----------------------------------------------------| v1 standard functions |----------------------------------------------------
----------------------------------------------------+-----------------------+----------------------------------------------------

-- Get card picture URI
function v1_visual_get_card_picture(edition)
  local uri = "https://cdn.steamgriddb.com/grid/e8cf1f5c9177fd140fd704cf74a2a2b9.png"
  local path = "/tmp/.star-rail-" .. edition .. "-card"

  if io.open(path, "rb") ~= nil then
    return path
  end

  local file = io.open(path, "w+")

  file:write(v1_network_http_get(uri))
  file:close()

  return path
end

-- Get background picture URI
function v1_visual_get_background_picture(edition)
  local uri = social_api(edition)["data"]["adv"]["background"]

  local path = "/tmp/.star-rail-" .. edition .. "-background"

  if io.open(path, "rb") ~= nil then
    return path
  end

  local file = io.open(path, "w+")

  file:write(v1_network_http_get(uri))
  file:close()

  return path
end

-- Get CSS styles for game details background
function v1_visual_get_details_background_css(edition)
  return "background: radial-gradient(circle, rgba(172,148,134,1) 30%, rgba(112,65,81,1) 100%);"
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
function v1_game_is_installed(game_path)
  return io.open(game_path .. "/UnityPlayer.dll", "rb") ~= nil
end

-- Get installed game version
function v1_game_get_version(game_path, edition)
  local file = io.open(game_path .. "/StarRail_Data/data.unity3d", "rb")

  if not file then
    return nil
  end

  file:seek("set", 4000)

  return file:read(10000):gmatch("[1-9]+[.][0-9]+[.][0-9]+")()
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
  local installed_version = v1_game_get_version(game_path, edition)

  if not installed_version then
    return nil
  end

  local game_data = game_api(edition)["data"]["game"]

  local latest_info = game_data["latest"]
  local diffs = game_data["diffs"]

  -- It should be impossible to have higher installed version
  -- but just in case I have to cover this case as well
  if compare_versions(installed_version, latest_info["version"]) ~= -1 then
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

-- Get installed game status before launching it
function v1_game_get_status(game_path, edition)
  return {
    ["allow_launch"] = false,
    ["severity"]     = "critical",
    ["reason"]       = "The game doesn't support launching yet"
  }
end

-- Get game launching options
function v1_game_get_launch_options(game_path, addons_path, edition)
  return {
    ["executable"]  = "StarRail.exe",
    ["options"]     = {},
    ["environment"] = {}
  }
end

-- Get game integrity info
function v1_game_get_integrity_info(game_path, edition)
  local base_uri = game_api(edition)["data"]["game"]["latest"]["decompressed_path"]
  local pkg_version = v1_network_http_get(base_uri .. "/pkg_version")

  local integrity = {}

  for line in pkg_version:gmatch("([^\n]*)\n") do
    if line ~= "" then
      local info = v1_json_decode(line)

      table.insert(integrity, {
        ["hash"]  = "md5",
        ["value"] = info["md5"]:lower(),

        ["file"] = {
          ["path"] = info["remoteName"],
          ["uri"]  = base_uri .. "/" .. info["remoteName"],
          ["size"] = info["fileSize"]
        }
      })
    end
  end

  return integrity
end

-- Get list of game addons (voice packages)
function v1_addons_get_list(edition)
  local latest_info = game_api(edition)["data"]["game"]["latest"]
  local voiceovers = {}

  for _, package in pairs(latest_info["voice_packs"]) do
    -- zh-tw is a copy of zh-cn
    if package["language"] ~= "zh-tw" then
      table.insert(voiceovers, {
        ["type"]     = "module",
        ["name"]     = package["language"],
        ["title"]    = get_voiceover_title(package["language"]),
        ["version"]  = latest_info["version"],
        ["required"] = false
      })
    end
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
    return io.open(addon_path .. "/StarRail_Data/Persistent/Audio/AudioPackage/Windows/" .. get_voiceover_folder(addon_name) .. "/VoBanks0.pck", "rb") ~= nil
  end

  return false
end

-- Get installed addon version
function v1_addons_get_version(group_name, addon_name, addon_path, edition)
  if group_name == "voiceovers" then
    local version = io.open(addon_path .. "/StarRail_Data/Persistent/Audio/AudioPackage/Windows/" .. get_voiceover_folder(addon_name) .. "/.version", "r")

    if version ~= nil then
      version = version:read("*all")

      -- Verify that stored version number is correct
      if split_version(version) ~= nil then
        return version
      end
    end
  end

  return nil
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

  if not installed_version then
    return nil
  end

  local game_data = game_api(edition)["data"]["game"]

  local latest_info = game_data["latest"]
  local diffs = game_data["diffs"]

  -- It should be impossible to have higher installed version
  -- but just in case I have to cover this case as well
  if compare_versions(installed_version, latest_info["version"]) ~= -1 then
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

-- Get addon files / folders paths
function v1_addons_get_paths(group_name, addon_name, addon_path, edition)
  if group_name == "voiceovers" then
    return {
      addon_path .. "/StarRail_Data/Persistent/Audio/AudioPackage/Windows/" .. get_voiceover_folder(addon_name)
    }
  end

  return {}
end

-- Get addon integrity info
function v1_addons_get_integrity_info(group_name, addon_name, addon_path, edition)
  -- There's no pkg_version per voiceover?
  return {}
end

-- Game update post-processing
function v1_game_diff_post_transition(game_path, edition)
  local file = io.open(game_path .. "/.version", "w+")

  local version = v1_game_get_version(game_path) or game_api(edition)["data"]["game"]["latest"]["version"]

  file:write(version)
  file:close()

  -- TODO: deletefiles.txt, hdifffiles.txt
end

-- Addon update post-processing
function v1_addons_diff_post_transition(group_name, addon_name, addon_path, edition)
  if group_name == "voiceovers" then
    local file = io.open(addon_path .. "/StarRail_Data/Persistent/Audio/AudioPackage/Windows/" .. get_voiceover_folder(addon_name) .. "/.version", "w+")

    local version = v1_addons_get_version(group_name, addon_name, addon_path, edition) or game_api(edition)["data"]["game"]["latest"]["version"]

    file:write(version)
    file:close()
  end

  -- TODO: deletefiles.txt, hdifffiles.txt
end
