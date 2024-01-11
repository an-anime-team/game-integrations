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

local jadeite_metadata = nil
local jadeite_download = nil

local function get_jadeite_metadata()
  local uri = "https://codeberg.org/mkrsym1/jadeite/raw/branch/master/metadata.json"

  if not jadeite_metadata then
    jadeite_metadata = v1_json_decode(v1_network_http_get(uri))
  end

  return jadeite_metadata
end

local function get_jadeite_download()
  local uri = "https://codeberg.org/api/v1/repos/mkrsym1/jadeite/releases/latest"

  if not jadeite_download then
    jadeite_download = v1_json_decode(v1_network_http_get(uri))
  end

  return jadeite_download
end

-- Convert raw number string into table of version numbers
local function split_version(version)
  if version == nil then
    return nil
  end

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
  local jadeite_metadata = get_jadeite_metadata()
  local jadeite_status   = jadeite_metadata["games"]["hsr"][edition]["status"]

  if jadeite_status == nil then
    return {
      ["allow_launch"] = false,
      ["severity"]     = "critical",
      ["reason"]       = "Failed to get patch status"
    }
  end

  local statuses = {
    -- Everything's fine, we've tried it on our mains (0% unsafe)
    ["verified"] = {
      ["allow_launch"] = true,
      ["severity"]     = "none"
    },

    -- We have no clue, but most likely everything is fine. Try it yourself (25% unsafe)
    ["unverified"] = {
      ["allow_launch"] = true,
      ["severity"]     = "warning",
      ["reason"]       = "Patch status is not verified"
    },

    -- Doesn't work at all (100% unsafe)
    ["broken"] = {
      ["allow_launch"] = false,
      ["severity"]     = "critical",
      ["reason"]       = "Patch doesn't work"
    },

    -- We're sure that you'll be banned. But the patch technically is working fine (100% unsafe)
    ["unsafe"] = {
      ["allow_launch"] = false,
      ["severity"]     = "critical",
      ["reason"]       = "Patch is unsafe to use"
    },

    -- We have some clue that you can be banned as there's some technical or other signs of it (75% unsafe)
    ["concerning"] = {
      ["allow_launch"] = true,
      ["severity"]     = "warning",
      ["reason"]       = "We have some concerns about current patch version"
    }
  }

  return statuses[jadeite_status]
end

-- Get game launching options
function v1_game_get_launch_options(game_path, addons_path, edition)
  return {
    ["executable"] = addons_path .. "/extra/jadeite/jadeite.exe",
    ["options"] = {
      "'Z:\\" .. game_path .. "/BH3.exe'",
      "--"
    },
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

-- Get list of game addons
function v1_addons_get_list(edition)
  local jadeite = get_jadeite_metadata()

  return {
    {
      ["name"]   = "extra",
      ["title"]  = "Extra",
      ["addons"] = {
        {
          ["type"]     = "component",
          ["name"]     = "jadeite",
          ["title"]    = "Jadeite",
          ["version"]  = jadeite["jadeite"]["version"],
          ["required"] = true
        }
      }
    }
  }
end

-- Check if addon is installed
function v1_addons_is_installed(group_name, addon_name, addon_path, edition)
  if group_name == "extra" and addon_name == "jadeite" then
    return io.open(addon_path .. "/jadeite.exe", "rb") ~= nil
  end

  return false
end

-- Get installed addon version
function v1_addons_get_version(group_name, addon_name, addon_path, edition)
  if group_name == "extra" and addon_name == "jadeite" then
    local version = io.open(addon_path .. "/.version", "r")

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
  if group_name == "extra" and addon_name == "jadeite" then
    local jadeite_metadata = get_jadeite_metadata()
    local jadeite_download = get_jadeite_download()

    -- Check release version tag
    if jadeite_download["tag_name"] == "v" .. jadeite_metadata["jadeite"]["version"] then
      return {
        ["version"] = jadeite_metadata["jadeite"]["version"],
        ["edition"] = edition,

        ["download"] = {
          ["type"] = "archive",
          ["size"] = jadeite_download["assets"][1]["size"],
          ["uri"]  = jadeite_download["assets"][1]["browser_download_url"]
        }
      }
    end
  end

  return nil
end

-- Get addon version diff
function v1_addons_get_diff(group_name, addon_name, addon_path, edition)
  if group_name == "extra" and addon_name == "jadeite" then
    local jadeite_metadata = get_jadeite_metadata()

    if compare_versions(installed_version, jadeite_metadata["jadeite"]["version"]) ~= -1 then
      return {
        ["current_version"] = installed_version,
        ["latest_version"]  = jadeite_metadata["jadeite"]["version"],

        ["edition"] = edition,
        ["status"]  = "latest"
      }
    else
      local jadeite_download = v1_addons_get_download(group_name, addon_name, addon_path, edition)

      if jadeite_download ~= nil then
        return {
          ["current_version"] = installed_version,
          ["latest_version"]  = jadeite_metadata["jadeite"]["version"],

          ["edition"] = edition,
          ["status"]  = "outdated",

          ["diff"] = jadeite_download["download"]
        }
      end
    end
  end

  return nil
end

-- Get addon files / folders paths
function v1_addons_get_paths(group_name, addon_name, addon_path, edition)
  if group_name == "extra" and addon_name == "jadeite" then
    return {
      addon_path
    }
  end

  return {}
end

-- Get addon integrity info
function v1_addons_get_integrity_info(group_name, addon_name, addon_path, edition)
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
  if group_name == "extra" and addon_name == "jadeite" then
    local file = io.open(addon_path .. "/.version", "w+")

    local version = get_jadeite_metadata()["jadeite"]["version"]

    file:write(version)
    file:close()
  end
end
