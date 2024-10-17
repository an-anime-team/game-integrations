local game_api_cache = {}
local social_api_cache = {}

local function get_game_biz(edition)
  local biz = {
    ["global"] = "hkrpg_global",
    ["china"]  = "hkrpg_cn"
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

local jadeite_metadata_cache = nil
local jadeite_download_cache = nil

local function get_jadeite_metadata()
  local uris = {
    "https://codeberg.org/mkrsym1/jadeite/raw/branch/master/metadata.json",
    "https://notabug.org/mkrsym1/jadeite-mirror/raw/master/metadata.json"
  }

  for _, uri in pairs(uris) do
    if jadeite_metadata_cache ~= nil then
      break
    end

    local response = v1_network_fetch(uri)

    if not response["ok"] then
      error("Failed to request jadeite metadata (code " .. response["status"] .. "): " .. response["statusText"])
    end

    jadeite_metadata_cache = response.json()
  end

  return jadeite_metadata_cache
end

local function get_jadeite_download()
  local uri = "https://codeberg.org/api/v1/repos/mkrsym1/jadeite/releases/latest"

  if not jadeite_download_cache then
    local response = v1_network_fetch(uri)

    if not response["ok"] then
      error("Failed to request jadeite releases (code " .. response["status"] .. "): " .. response["statusText"])
    end

    jadeite_download_cache = response.json()
  end

  return jadeite_download_cache
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

  local path = "/tmp/.star-rail-" .. edition .. "-background"

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

  file:seek("set", 3000)

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
      "'Z:\\" .. game_path .. "/StarRail.exe'",
      "--"
    },
    ["environment"] = {}
  }
end

-- Check if the game is running
function v1_game_is_running(game_path, edition)
  local handle = io.popen("ps -A", "r")
  local result = handle:read("*a")

  handle:close()

  return result:find("StarRail.exe")
end

-- Kill running game process
function v1_game_kill(game_path, edition)
  os.execute("pkill -f StarRail.exe")
  os.execute("pkill -f jadeite.exe")
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
  local latest_info = game_api(edition)["main"]["major"]
  local voiceovers = {}

  for _, package in pairs(latest_info["audio_pkgs"]) do
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

  local jadeite = get_jadeite_metadata()

  return {
    {
      ["name"]   = "voiceovers",
      ["title"]  = "Voiceovers",
      ["addons"] = voiceovers
    },
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
  if group_name == "voiceovers" then
    return io.open(addon_path .. "/StarRail_Data/Persistent/Audio/AudioPackage/Windows/" .. get_voiceover_folder(addon_name) .. "/VoBanks0.pck", "rb") ~= nil
  elseif group_name == "extra" and addon_name == "jadeite" then
    return io.open(addon_path .. "/jadeite.exe", "rb") ~= nil
  end

  return false
end

-- Get installed addon version
function v1_addons_get_version(group_name, addon_name, addon_path, edition)
  if group_name == "voiceovers" then
    local version = read_version_file(addon_path .. "/StarRail_Data/Persistent/Audio/AudioPackage/Windows/" .. get_voiceover_folder(addon_name) .. "/.version")
    if version then
      return string.format("%d.%d.%d", version.major, version.minor, version.patch)
    end
  elseif group_name == "extra" and addon_name == "jadeite" then
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
  if group_name == "voiceovers" then
    local latest_info = game_api(edition)["main"]["major"]

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
  elseif group_name == "extra" and addon_name == "jadeite" then
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
  local installed_version = v1_addons_get_version(group_name, addon_name, addon_path, edition)

  if not installed_version then
    return nil
  end

  if group_name == "voiceovers" then
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
  elseif group_name == "extra" and addon_name == "jadeite" then
    local jadeite_metadata = get_jadeite_metadata()

    if compare_string_versions(installed_version, jadeite_metadata["jadeite"]["version"]) ~= -1 then
      return {
        ["current_version"] = installed_version,
        ["latest_version"]  = jadeite_metadata["jadeite"]["version"],

        ["edition"] = edition,
        ["status"]  = "latest"
      }
    else
      local jadeite_download = v1_addons_get_download(group_name, addon_name, edition)

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
  if group_name == "voiceovers" then
    return {
      addon_path .. "/StarRail_Data/Persistent/Audio/AudioPackage/Windows/" .. get_voiceover_folder(addon_name)
    }
  elseif group_name == "extra" and addon_name == "jadeite" then
    return {
      addon_path
    }
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

-- Get addon integrity info
function v1_addons_get_integrity_info(group_name, addon_name, addon_path, edition)
  -- There's no pkg_version per voiceover?
  return {}
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
    local path = addon_path .. "/StarRail_Data/Persistent/Audio/AudioPackage/Windows/" .. get_voiceover_folder(addon_name) .. "/.version"
    write_version_file(path, version)
  elseif group_name == "extra" and addon_name == "jadeite" then
    local file = io.open(addon_path .. "/.version", "w+")
    local version = get_jadeite_metadata()["jadeite"]["version"]

    if file ~= nil and version ~= nil then
      file:write(version)
      file:close()
    end
  end
end

-- Addon update post-processing
function v1_addons_diff_post_transition(group_name, addon_name, addon_path, edition)
  if group_name == "voiceovers" then
    process_hdifffiles(addon_path, edition)
    process_deletefiles(addon_path, edition)
  end
end
