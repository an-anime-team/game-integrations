local game_api_cache = {}
local social_api_cache = {}

local function game_api(edition)
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

local function social_api(edition)
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

----------------------------------------------------+-----------------------+----------------------------------------------------
----------------------------------------------------| v1 standard functions |----------------------------------------------------
----------------------------------------------------+-----------------------+----------------------------------------------------

-- Get card picture URI
function v1_visual_get_card_picture(edition)
  local uri = "https://cdn.steamgriddb.com/grid/dad17817cb7f0d4655bbe4460538f1ab.jpg"
  local path = "/tmp/.honkai-" .. edition .. "-card"

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

  local path = "/tmp/.honkai-" .. edition .. "-background"

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
  return "background: radial-gradient(circle, rgba(177,132,89,1) 30%, rgba(72,80,167,1) 100%);"
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
      ["title"] = "Taiwan"
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
function v1_game_get_version(game_path, edition)
  local file = io.open(game_path .. "/BH3_Data/globalgamemanagers", "rb")

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
    ["executable"]  = "BH3.exe",
    ["options"]     = {},
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
  return nil
end

-- Get full addon downloading info
function v1_addons_get_download(group_name, addon_name, edition)
  return nil
end

-- Get addon version diff
function v1_addons_get_diff(group_name, addon_name, addon_path, edition)
  return nil
end

function v1_addons_get_paths(group_name, addon_name, addon_path, edition)
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

-- Addons update post-processing
function v1_addons_diff_post_transition(group_name, addon_name, addon_path, edition)
  
end
