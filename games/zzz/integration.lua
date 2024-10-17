local game_api_cache = {}
local social_api_cache = {}

local function game_api(edition)
  if game_api_cache[edition] == nil then
    local uri = {
      ["global"] = "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getGamePackages?launcher_id=VYTpXlbWo8",
      ["china"]  = "https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getGamePackages?launcher_id=jGHBHlcOq1"
    }

    local response = v1_network_fetch(uri[edition])

    if not response["ok"] then
      error("Failed to request game API (code " .. response["status"] .. "): " .. response["statusText"])
    end

    local biz = {
      ["global"] = "nap_global",
      ["china"]  = "nap_cn"
    }
    local game_packages = response.json()["data"]["game_packages"]
    local game_info
    for _, pkg in ipairs(game_packages) do
      if pkg["game"]["biz"] == biz[edition] then
        game_info = pkg
        break
      end
    end

    if not game_info then
      error("Failed to find game packages")
    end
    game_api_cache[edition] = game_info
  end

  return game_api_cache[edition]
end

local function social_api(edition)
  if social_api_cache[edition] == nil then
    local uri = {
      ["global"] = "https://sg-hyp-api.hoyoverse.com/hyp/hyp-connect/api/getAllGameBasicInfo?launcher_id=VYTpXlbWo8&language=en-us",
      ["china"]  = "https://hyp-api.mihoyo.com/hyp/hyp-connect/api/getAllGameBasicInfo?launcher_id=jGHBHlcOq1"
    }

    local response = v1_network_fetch(uri[edition])

    if not response["ok"] then
      error("Failed to request social API (code " .. response["status"] .. "): " .. response["statusText"])
    end

    social_api_cache[edition] = response.json()
  end

  return social_api_cache[edition]
end

local function get_hdiff(edition)
  local uri = {
    ["global"] = "https://github.com/an-anime-team/anime-game-core/raw/main/external/hpatchz/hpatchz",

    -- Github is blocked in China so we're using a mirror here
    ["china"]  = "https://hub.gitmirror.com/https://raw.githubusercontent.com/an-anime-team/anime-game-core/main/external/hpatchz/hpatchz"
  }

  if not io.open("/tmp/hpatchz", "rb") then
    local response = v1_network_fetch(uri[edition])

    if not response["ok"] then
      error("Failed to download hpatchz binary (code " .. response["status"] .. "): " .. response["statusText"])
    end

    local file = io.open("/tmp/hpatchz", "wb+")

    file:write(response["body"])
    file:close()

    -- Make downloaded binary executable
    os.execute("chmod +x /tmp/hpatchz")
  end

  return "/tmp/hpatchz"
end

local function apply_hdiff(hdiff_path, file, patch, output)
  local handle = io.popen(hdiff_path .. " -f '" .. file .. "' '" .. patch .. "' '" .. output .. "'", "r")
  local result = handle:read("*a")

  handle:close()

  return result:find("patch ok!")
end

-- Convert raw number string into table of version numbers
local function split_version(version)
  if version == nil then
    return nil
  end

  local numbers = version:gmatch("([1-9]+)%.([0-9]+)%.([0-9]+)")

  for major, minor, patch in numbers do
    return {
      ["major"] = tonumber(major),
      ["minor"] = tonumber(minor),
      ["patch"] = tonumber(patch),
    }
  end

  return nil
end

-- Compare two structural versions
--
-- Structural version expect version parameters are like the output of split_version.
-- [ 1] if version_1 > version_2
-- [ 0] if version_1 = version_2
-- [-1] if version_1 < version_2
local function compare_structural_versions(version_1, version_2)
  if version_1.major > version_2.major then return  1 end
  if version_1.major < version_2.major then return -1 end

  if version_1.minor > version_2.minor then return  1 end
  if version_1.minor < version_2.minor then return -1 end

  if version_1.patch > version_2.patch then return  1 end
  if version_1.patch < version_2.patch then return -1 end

  return 0
end

-- Compare two raw version strings
-- [ 1] if version_1 > version_2
-- [ 0] if version_1 = version_2
-- [-1] if version_1 < version_2
local function compare_string_versions(version_1, version_2)
  local version_1 = split_version(version_1)
  local version_2 = split_version(version_2)

  if version_1 == nil or version_2 == nil then
    return nil
  end

  return compare_structural_versions(version_1, version_2)
end

-- Reads a file of 3 byes and convert the content into a structural version.
--
-- Returns nil on error for fail-open.
local function read_binary_version(filepath)
  local file = io.open(filepath, "rb")

  if not file then
    return nil, "Failed to open file"
  end

  -- Read the 3 bytes from the file
  local version_bytes = file:read(3)
  file:close()
  -- Check if we have read exactly 3 bytes
  if not version_bytes or #version_bytes ~= 3 then
    -- Fail open if the file is malformatted
    return nil
  end

  local major = string.byte(version_bytes, 1)
  local minor = string.byte(version_bytes, 2)
  local patch = string.byte(version_bytes, 3)

  return {
      ["major"] = major,
      ["minor"] = minor,
      ["patch"] = patch,
  }
end

local function get_edition_data_folder()
  return "ZenlessZoneZero_Data"
end

----------------------------------------------------+-----------------------+----------------------------------------------------
----------------------------------------------------| v1 standard functions |----------------------------------------------------
----------------------------------------------------+-----------------------+----------------------------------------------------

-- Get card picture URI
function v1_visual_get_card_picture(edition)
  local uri = "https://cdn2.steamgriddb.com/grid/97657e12f1b8cbf71b6837f02b23d423.png"
  local path = "/tmp/.zzz-" .. edition .. "-card"

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

-- Get background picture URI
function v1_visual_get_background_picture(edition)
  local biz = {
    ["global"] = "nap_global",
    ["china"]  = "nap_cn"
  }
  local game_infos = social_api(edition)["data"]["game_info_list"]
  local game_info
  for _, info in ipairs(game_infos) do
    if info["game"]["biz"] == biz[edition] then
      game_info = info
      break
    end
  end

  if not game_info then
    error("Failed to find background info.")
  end

  local uri = game_info["backgrounds"][0]["background"]["url"]

  local path = "/tmp/.zzz-" .. edition .. "-background"

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

-- Get CSS styles for game details background
function v1_visual_get_details_background_css(edition)
  return "background: radial-gradient(circle, rgba(168,144,111,1) 30%, rgba(88,88,154,1) 100%);"
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
  local file = io.open(game_path .. "/" .. get_edition_data_folder(edition) .. "/globalgamemanagers", "rb")

  if not file then
    return nil
  end

  file:seek("set", 4000)

  local version = file:read(10000):gmatch("[1-9]+[.][0-9]+[.][0-9]+")()

  -- Try to read the version from .version file. This fils is written by the
  -- update process with the value taken from the API that include the
  -- correct patch version (e.g 1.0.1).
  local version_2 = read_binary_version(game_path .. "/.version")
  if not version_2 then
    return version
  end

  local version_1 = split_version(version)
  if compare_structural_versions(version_1, version_2) == -1 then
    return string.format("%d.%d.%d", version_2.major, version_2.minor, version_2.patch)
  end

  return version
end

-- Get full game downloading info
function v1_game_get_download(edition)
  local latest_info = game_api(edition)["main"]["major"]
  local segments = {}
  local size = 0

  for _, segment in pairs(latest_info["game_pkgs"]) do
    table.insert(segments, segment["url"])

    size = size + segment["size"]
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

  local game_data = game_api(edition)

  local latest_info = game_data["main"]["major"]
  local patches = game_data["main"]["patches"]

  -- It should be impossible to have higher installed version
  -- but just in case I have to cover this case as well
  if compare_string_versions(installed_version, latest_info["version"]) ~= -1 then
    return {
      ["current_version"] = installed_version,
      ["latest_version"]  = latest_info["version"],

      ["edition"] = edition,
      ["status"]  = "latest"
    }
  end

  for _, patch in ipairs(patches) do
    if patch["version"] == installed_version then
      return {
        ["current_version"] = installed_version,
        ["latest_version"]  = latest_info["version"],

        ["edition"] = edition,
        ["status"]  = "outdated",

        ["diff"] = {
          ["type"] = "archive",
          ["size"] = patch["game_pkgs"][1]["size"],
          ["uri"]  = patch["game_pkgs"][1]["url"]
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

-- Get installed game status before launching it
function v1_game_get_status(game_path, edition)
  return {
    ["allow_launch"] = true,
    ["severity"] = "none"
  }
end

-- Get game launching options
function v1_game_get_launch_options(game_path, addons_path, edition)
  return {
    ["executable"]  = "ZenlessZoneZero.exe",
    ["options"]     = {},
    ["environment"] = {}
  }
end

-- Check if the game is running
function v1_game_is_running(game_path, edition)
  local process_name = "ZenlessZoneZero.exe"

  local handle = io.popen("ps -A", "r")
  local result = handle:read("*a")

  handle:close()

  return result:find(process_name)
end

-- Kill running game process
function v1_game_kill(edition)
  local process_name = "ZenlessZoneZero.exe"

  os.execute("pkill -f " .. process_name)
end

-- Get game integrity info
function v1_game_get_integrity_info(game_path, edition)
  --- ZZZ has no integrity info yet
  return {}
end

-- Get list of game addons (voice packages)
function v1_addons_get_list(edition)
  -- ZZZ has no per-language voice packages yet
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
end

-- Get addon files / folders paths
function v1_addons_get_paths(group_name, addon_name, addon_path, edition)
  return {}
end

-- Get addon integrity info
function v1_addons_get_integrity_info(group_name, addon_name, addon_path, edition)
  return {}
end

local function process_hdifffiles(path, edition)
  local hdifffiles = io.open(path .. "/hdifffiles.txt", "r")

  if not hdifffiles then
    return
  end

  local hdiff = get_hdiff(edition)

  -- {"remoteName": "AnimeGame_Data/StreamingAssets/Audio/GeneratedSoundBanks/Windows/Japanese/1001.pck"}
  for line in hdifffiles:lines() do
    local file_info = v1_json_decode(line)

    local file   = path .. "/" .. file_info["remoteName"]
    local patch  = path .. "/" .. file_info["remoteName"] .. ".hdiff"
    local output = path .. "/" .. file_info["remoteName"] .. ".hdiff_patched"

    if not apply_hdiff(hdiff, file, patch, output) then
      error("Failed to apply hdiff to file" .. file)
    end

    os.remove(file)
    os.remove(patch)

    os.rename(output, file)
  end

  os.remove(path .. "/hdifffiles.txt")
end

local function process_deletefiles(path, edition)
  local txt = io.open(path .. "/deletefiles.txt", "r")
  if not txt then
    return
  end

  -- AnimeGame_Data/Plugins/metakeeper.dll
  for line in txt:lines() do
    os.remove(path .. "/" .. line)
  end

  os.remove(path .. "/deletefiles.txt")
end

-- Game update processing
function v1_game_diff_transition(game_path, edition)
  local file = io.open(game_path .. "/.version", "wb")
  local version = split_version(game_api(edition)["main"]["major"]["version"])

  file:write(string.char(version.major, version.minor, version.patch))
  file:close()
end

-- Game update post-processing
function v1_game_diff_post_transition(game_path, edition)
  process_hdifffiles(game_path, edition)
  process_deletefiles(game_path, edition)
end

-- Addon update processing
function v1_addons_diff_transition(group_name, addon_name, addon_path, edition)
end

-- Addon update post-processing
function v1_addons_diff_post_transition(group_name, addon_name, addon_path, edition)
end
