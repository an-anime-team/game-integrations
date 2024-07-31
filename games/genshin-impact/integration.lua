local game_api_cache = {}
local social_api_cache = {}

local function get_game_biz(edition)
  local biz = {
    ["global"] = "hk4e_global",
    ["china"]  = "hk4e_cn"
  }
  return biz[edition]
end

local function lookup_game_info(games, edition)
  local biz = get_game_biz(edition)
  for _, game_info in ipairs(games) do
    if game_info["game"]["biz"] == biz then
      return game_info
    end
  end
  return nil
end

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

    local game_packages = response.json()["data"]["game_packages"]
    local game_info = lookup_game_info(game_packages, edition)

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
      ["major"] = major,
      ["minor"] = minor,
      ["patch"] = patch
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

--- Write a version to a file in binary format
--- version can be either a string version or a structural version
local function write_version_file(path, version)
  local file = io.open(path, "wb+")
  local structural_version
  if type(version) == 'string' then
    structural_version = split_version(version)
  else
    structural_version = version
  end

  file:write(string.char(structural_version.major, structural_version.minor, structural_version.patch))
  file:close()
end

-- Reads a binary or string version file and returns a structural version
--
-- Returns nil on error for fail-open.
local function read_version_file(filepath)
  local file = io.open(filepath, "rb")

  if not file then
    return nil, "Failed to open file"
  end

  -- Read the 3 bytes from the file
  local version_bytes = file:read(100)
  file:close()
  -- Check if we have read exactly 3 bytes
  if #version_bytes > 3 then
    -- The content is likely a string version, created by older version of the integration
    return split_version(version_bytes)
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
    ["en-us"] = "English(US)",
    ["ja-jp"] = "Japanese",
    ["ko-kr"] = "Korean",
    ["zh-cn"] = "Chinese"
  }

  return names[language] or language
end

local function get_edition_data_folder(edition)
  local names = {
    ["global"] = "GenshinImpact_Data",
    ["china"]  = "YuanShen_Data"
  }

  return names[edition]
end

----------------------------------------------------+-----------------------+----------------------------------------------------
----------------------------------------------------| v1 standard functions |----------------------------------------------------
----------------------------------------------------+-----------------------+----------------------------------------------------

-- Get card picture URI
function v1_visual_get_card_picture(edition)
  local uri = "https://cdn.steamgriddb.com/grid/393b37dd7097776b1b56b10897e1a054.png"
  local path = "/tmp/.genshin-" .. edition .. "-card"

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
  local game_infos = social_api(edition)["data"]["game_info_list"]
  local game_info = lookup_game_info(game_infos, edition)
  if not game_info then
    error("Failed to find background info.")
  end

  local uri = game_info["backgrounds"][0]["background"]["url"]

  local path = "/tmp/.genshin-" .. edition .. "-background"

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

  return file:read(10000):gmatch("[1-9]+[.][0-9]+[.][0-9]+")()
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
  local executable = {
    ["global"] = "GenshinImpact.exe",
    ["china"]  = "YuanShen.exe"
  }

  return {
    ["executable"]  = executable[edition],
    ["options"]     = {},
    ["environment"] = {}
  }
end

-- Check if the game is running
function v1_game_is_running(game_path, edition)
  local process_name = {
    ["global"] = "GenshinImpact.e",
    ["china"]  = "YuanShen.exe"
  }

  local handle = io.popen("ps -A", "r")
  local result = handle:read("*a")

  handle:close()

  return result:find(process_name[edition])
end

-- Kill running game process
function v1_game_kill(game_path, edition)
  local process_name = {
    ["global"] = "GenshinImpact.e",
    ["china"]  = "YuanShen.exe"
  }

  os.execute("pkill -f " .. process_name[edition])
end

-- Get game integrity info
function v1_game_get_integrity_info(game_path, edition)
  local base_uri = game_api(edition)["main"]["major"]["res_list_url"]
  if base_uri == nil or base_uri == '' then
    return {}
  end
  local pkg_version = v1_network_fetch(base_uri .. "/pkg_version")

  if not pkg_version["ok"] then
    error("Failed to request game integrity info (code " .. pkg_version["status"] .. "): " .. pkg_version["statusText"])
  end

  local integrity = {}

  for line in pkg_version["body"]:gmatch("([^\n]*)\n") do
    if line ~= "" then
      local info = v1_json_decode(line)

      table.insert(integrity, {
        ["hash"]  = "md5",
        ["value"] = info["md5"],

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
  local latest_info = game_api(edition)["main"]["major"]
  local voiceovers = {}

  for _, package in pairs(latest_info["audio_pkgs"]) do
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
    return io.open(addon_path .. "/" .. get_edition_data_folder(edition) .. "/StreamingAssets/AudioAssets/" .. get_voiceover_folder(addon_name) .. "/1001.pck", "rb") ~= nil
  end

  return false
end

-- Get installed addon version
function v1_addons_get_version(group_name, addon_name, addon_path, edition)
  if group_name == "voiceovers" then
    local version = read_version_file(addon_path .. "/" .. get_edition_data_folder(edition) .. "/StreamingAssets/AudioAssets/" .. get_voiceover_folder(addon_name) .. "/.version")
    if version then
      return string.format("%d.%d.%d", version.major, version.minor, version.patch)
    end
  end

  return nil
end

-- Get full addon downloading info
function v1_addons_get_download(group_name, addon_name, edition)
  local latest_info = game_api(edition)["main"]["major"]

  if group_name == "voiceovers" then
    for _, package in pairs(latest_info["audio_pkgs"]) do
      if package["language"] == addon_name then
        return {
          ["version"] = latest_info["version"],
          ["edition"] = edition,

          ["download"] = {
            ["type"] = "archive",
            ["size"] = package["size"],
            ["uri"]  = package["url"]
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

  local game_data = game_api(edition)["main"]

  local latest_info = game_data["major"]
  local diffs = game_data["patches"]

  -- It should be impossible to have higher installed version
  -- but just in case I have to cover this case as well
  if compare_string_versions(installed_version, latest_info["version"]) ~= -1 then
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
          for _, package in pairs(diff["audio_pkgs"]) do
            if package["language"] == addon_name then
              return {
                ["current_version"] = installed_version,
                ["latest_version"]  = latest_info["version"],

                ["edition"] = edition,
                ["status"]  = "outdated",

                ["diff"] = {
                  ["type"] = "archive",
                  ["size"] = package["size"],
                  ["uri"]  = package["url"]
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
      addon_path .. "/" .. get_edition_data_folder(edition) .. "/StreamingAssets/AudioAssets/" .. get_voiceover_folder(addon_name),
      addon_path .. "/Audio_" .. get_voiceover_folder(addon_name) .. "_pkg_version"
    }
  end

  return {}
end

-- Get addon integrity info
function v1_addons_get_integrity_info(group_name, addon_name, addon_path, edition)
  if group_name == "voiceovers" then
    local base_uri = game_api(edition)["main"]["major"]["res_list_url"]
    if base_uri == nil or base_uri == '' then
      return {}
    end
    local pkg_version = v1_network_fetch(base_uri .. "/Audio_" .. get_voiceover_folder(addon_name) .. "_pkg_version")

    if not pkg_version["ok"] then
      error("Failed to request addon integrity info (code " .. pkg_version["status"] .. "): " .. pkg_version["statusText"])
    end

    local integrity = {}

    for line in pkg_version["body"]:gmatch("([^\n]*)\n") do
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

  return {}
end

local function process_hdifffiles(path, edition)
  local hdifffiles = io.open(path .. "/hdifffiles.txt", "r")

  if not hdifffiles then
    return
  end

  local hdiff = get_hdiff(edition)
  local base_uri = game_api(edition)["main"]["major"]["res_list_url"]

  -- {"remoteName": "AnimeGame_Data/StreamingAssets/Audio/GeneratedSoundBanks/Windows/Japanese/1001.pck"}
  for line in hdifffiles:lines() do
    local file_info = v1_json_decode(line)

    local file   = path .. "/" .. file_info["remoteName"]
    local patch  = path .. "/" .. file_info["remoteName"] .. ".hdiff"
    local output = path .. "/" .. file_info["remoteName"] .. ".hdiff_patched"

    if not apply_hdiff(hdiff, file, patch, output) then
      if base_uri == nil or base_uri == '' then
        error("Failed apply diff for file " .. file)
      end
      local response = v1_network_fetch(base_uri .. "/" .. file_info["remoteName"])

      if not response["ok"] then
        error("Failed to download file (code " .. response["status"] .. "): " .. response["statusText"])
      end

      local file = io.open(output, "wb+")

      file:write(response["body"])
      file:close()
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
  local path = game_path .. "/.version"
  local version = v1_game_get_version(game_path, edition) or game_api(edition)["main"]["major"]["version"]

  write_version_file(path, version)
end

-- Game update post-processing
function v1_game_diff_post_transition(game_path, edition)
  process_hdifffiles(game_path, edition)
  process_deletefiles(game_path, edition)
end

-- Addon update processing
function v1_addons_diff_transition(group_name, addon_name, addon_path, edition)
  if group_name == "voiceovers" then
    local version = v1_addons_get_version(group_name, addon_name, addon_path, edition) or game_api(edition)["main"]["major"]["version"]
    local path = addon_path .. "/" .. get_edition_data_folder(edition) .. "/StreamingAssets/AudioAssets/" .. get_voiceover_folder(addon_name) .. "/.version"
    write_version_file(path, version)
  end
end

-- Addon update post-processing
function v1_addons_diff_post_transition(group_name, addon_name, addon_path, edition)
  if group_name == "voiceovers" then
    process_hdifffiles(addon_path, edition)
    process_deletefiles(addon_path, edition)
  end
end
