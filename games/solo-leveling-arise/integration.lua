--!/usr/bin/lua

local game_api_cache = {}

function game_api(edition)
  if game_api_cache[edition] == nil then 
    local uri = {
      ["global"] = "https://apis.netmarble.com/cpplauncher/api/game/sololv/builds?buildCode=A"
    }
    local header = {
      ["global"] = {
        ["headers"] = {
          ["X-NM-LAUNCHER-CH"] = "ypWjRL2aNi",
          ["X-NM-LAUNCHER-IGS"] = "c29sb2x2X0E="
        }
      }
    }

    local response = v1_network_fetch(uri[edition], header[edition])

    if not response["ok"] then
      error("Failed to request game API (code " .. response["status"] .. "): " .. response["statusText"])
    end

    game_api_cache[edition] = response.json()
  end

  return game_api_cache[edition]
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

function v1_game_get_editions_list() 
  return {
    {
      ["name"] = "global",
      ["title"] = "Global"
    }
  }
end

function v1_visual_get_card_picture(edition)
  local uri = "https://sgimage.netmarble.com/images/netmarble/sololv/20230323/ocai1679554746714.jpg"
  local path = "/tmp/.sololeveling-" .. edition .. "-card"

  if io.open(path, "rb") ~= nil then
    return path
  end

  local response = v1_network_fetch(uri) 

  if not response["ok"] then
    error("Failed to download card picture (code " .. response["status"] .. "): " .. response["statusText"])
  end

  local file = io.open(path, "wb+")

  file:write(response["body"])
  file:close()

  return path
end

function v1_visual_get_background_picture(edition) 
  local uri = "https://sgimage.netmarble.com/images/netmarble/sololv/20230313/r20w1678676611229.jpg"
  local path = "/tmp/.sololeveling-" .. edition .. "-background"

  if io.open(path, "rb") ~= nil then
    return path
  end

  local response = v1_network_fetch(uri) 

  if not response["ok"] then
    error("Failed to download background picture (code " .. response["status"] .. "): " .. response["statusText"])
  end

  local file = io.open(path, "wb+")

  file:write(response["body"])
  file:close()  

  return path
end

function v1_game_is_installed(game_path)
  return io.open(game_path .. "/UnityPlayer.dll", "rb") ~= nil
end

function v1_game_get_version(game_path, edition)
  local file = io.open(game_path .. "/.version")
 
  if not file then
    return nil
  end

  local version = file:read("l")

  if not version then
    error("No version in .version file")
  end

  return version
end

function v1_game_get_download(edition)
  local latest_info = game_api(edition)["data"]

  return {
    ["version"] = latest_info["buildVersion"],
    ["edition"] = edition,
    ["download"] = {
      ["type"] = "archive",
      ["size"] = latest_info["buildFileSizeByte"],
      ["uri"] = latest_info["buildDownloadUrl"],
    }
  }
end

function v1_game_get_diff(game_path, edition)
  local installed_version = v1_game_get_version(game_path, edition)

  if not installed_version then
    return nil
  end

  local game_data = game_api(edition)["data"]

  -- List of diffs
  local diffs = game_data["partialFileList"] 

  if compare_versions(installed_version, game_data["buildVersion"]) ~= -1 then
    return {
      ["current_version"] = installed_version,
      ["latest_version"] = game_data["buildVersion"],
      ["edition"] = edition,
      ["status"] = "latest"
    }
  else
    -- Select the latest diff
    local diff = diffs[1]
    if compare_versions(installed_version, game_data["buildVersion"]) then
      return {
        ["current_version"] = installed_version,
        ["latest_version"] = game_data["buildVersion"],
        ["edition"] = edition,
        ["status"] = "outdated",
        ["diff"] = {
          ["type"] = "archive",
          ["size"] = diff["fileSizeByte"],
          ["uri"] = diff["downloadUrl"],
        }
      }
    end
  end

  return {
    ["current_version"] = installed_version,
    ["latest_version"] = game_data["buildVersion"],
    ["edition"] = edition,
    ["status"] = "unavailable"
  }
end

function v1_game_get_status(game_path, edition)
  return {
    ["allow_launch"] = true,
    ["severity"] = "none"
  }
end

function v1_game_get_launch_options(game_path, addons_path, edition)
  local executable = {
    ["global"] = "Solo_Leveling_ARISE.exe"
  }

  return {
    ["executable"] = executable[edition],
    ["options"] = {},
    ["environment"] = {}
  }
end

function v1_game_is_running(game_path, edition)
  local process_name = {
    ["global"] = "Solo_Leveling_A"
  } 

  local handle = io.popen("ps -A", "r")
  local result = handle:read("*a")

  handle:close()

  return result:find(process_name[edition])
end

function v1_game_kill(game_path, edition)
  local process_name = {
    ["global"] = "Solo_Leveling_A"
  }

  os.execute("pkill -f " .. process_name[edition])
end

function v1_game_diff_post_transition(path, edition)
  local file = io.open(path .. "/.version", "w") 

  if not file then
    return nil
  end

  local game_data = game_api(edition)["data"]

  file:write(game_data["buildVersion"])
end

-- TODO: I am not aware of any server-side integrity info being available, maybe would have to redownload the game. 
function v1_game_get_integrity_info(game_path, edition)
  return {}
end

-- There are no addons
function v1_addons_get_list(edition)
  return {}
end
function v1_addons_is_installed(group_name, addon_name, addon_path, edition)
  return true
end
function v1_addons_get_version(group_name, addon_name, addon_path, edition)
  return nil
end
function v1_addons_get_download(group_name, addon_name, edition)
  return nil
end
function v1_addons_get_diff(group_name, addon_name, addon_path, edition)
  return addon_path 
end
function v1_addons_get_integrity_info(group_name, addon_name, addon_path, edition)
  return nil
end
