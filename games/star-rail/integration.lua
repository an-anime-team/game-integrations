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

local jadeite_metadata = nil
local jadeite_download = nil

local function get_jadeite_metadata()
  local uris = {
    "https://codeberg.org/mkrsym1/jadeite/raw/branch/master/metadata.json",
    "https://notabug.org/mkrsym1/jadeite-mirror/raw/master/metadata.json"
  }

  for _, uri in pairs(uris) do
    if jadeite_metadata ~= nil then
      break
    end

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

local function get_hdiff(edition)
  local uri = {
    ["global"] = "https://github.com/an-anime-team/anime-game-core/raw/main/external/hpatchz/hpatchz",

    -- Github is blocked in China so we're using a mirror here
    ["china"]  = "https://hub.gitmirror.com/https://raw.githubusercontent.com/an-anime-team/anime-game-core/main/external/hpatchz/hpatchz"
  }

  if not io.open("/tmp/hpatchz", "rb") then
    local file = io.open("/tmp/hpatchz", "bw+")

    file:write(v1_network_http_get(uri[edition]))
    file:close()
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

  file:seek("set", 2000)

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

  local jadeite = get_jadeite_metadata()
  local hdiff   = get_hdiff_info()

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
        },
        {
          ["type"]     = "component",
          ["name"]     = "hdiffpatch",
          ["title"]    = "HDiffPatch",
          ["version"]  = hdiff["version"], -- TODO: will crash if get_hdiff_info() is nil
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
  elseif group_name == "extra" and addon_name == "hdiffpatch" then
    return io.open(addon_path .. "/linux64/hpatchz", "rb") ~= nil
  end

  return false
end

-- Get installed addon version
function v1_addons_get_version(group_name, addon_name, addon_path, edition)
  local version = nil

  if group_name == "voiceovers" then
    version = io.open(addon_path .. "/StarRail_Data/Persistent/Audio/AudioPackage/Windows/" .. get_voiceover_folder(addon_name) .. "/.version", "r")
  elseif group_name == "extra" and addon_name == "jadeite" then
    version = io.open(addon_path .. "/.version", "r")
  elseif group_name == "extra" and addon_name == "hdiffpatch" then
    version = io.open(addon_path .. "/.version", "r")
  end

  if version ~= nil then
    version = version:read("*all")

    -- Verify that stored version number is correct
    if split_version(version) ~= nil then
      return version
    end
  end

  return nil
end

-- Get full addon downloading info
function v1_addons_get_download(group_name, addon_name, edition)
  if group_name == "voiceovers" then
    local latest_info = game_api(edition)["data"]["game"]["latest"]

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
  elseif group_name == "extra" and addon_name == "hdiffpatch" then
    local latest_info = get_hdiff_info()

    if latest_info ~= nil then
      return {
        ["version"] = latest_info["version"],
        ["edition"] = edition,
  
        ["download"] = {
          ["type"] = "archive",
          ["size"] = latest_info["size"],
          ["uri"]  = latest_info["uri"]
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
  elseif group_name == "extra" and addon_name == "jadeite" then
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
  elseif group_name == "extra" and addon_name == "hdiffpatch" then
    local latest_info = get_hdiff_info()

    if compare_versions(installed_version, latest_info["version"]) ~= -1 then
      return {
        ["current_version"] = installed_version,
        ["latest_version"]  = latest_info["version"],

        ["edition"] = edition,
        ["status"]  = "latest"
      }
    else
      local hdiff_download = v1_addons_get_download(group_name, addon_name, addon_path, edition)

      if hdiff_download ~= nil then
        return {
          ["current_version"] = installed_version,
          ["latest_version"]  = latest_info["version"],
  
          ["edition"] = edition,
          ["status"]  = "outdated",
  
          ["diff"] = hdiff_download["download"]
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
  elseif group_name == "extra" and addon_name == "hdiffpatch" then
    return {
      addon_path
    }
  end

  return {}
end

local function process_hdifffiles(game_path, edition)
  local hdiff = get_hdiff(edition)
  local base_uri = game_api(edition)["data"]["game"]["latest"]["decompressed_path"]

  -- {"remoteName": "AnimeGame_Data/StreamingAssets/Audio/GeneratedSoundBanks/Windows/Japanese/1001.pck"}
  for line in io.lines(game_path .. "/hdifffiles.txt") do
    local file_info = v1_json_decode(line)

    local file   = game_path .. "/" .. file_info["remoteName"]
    local patch  = game_path .. "/" .. file_info["remoteName"] .. ".hdiff"
    local output = game_path .. "/" .. file_info["remoteName"] .. ".hdiff_patched"

    if not apply_hdiff(hdiff, file, patch, output) then
      local file = io.open(output, "bw+")

      file:write(v1_network_http_get(base_uri .. "/" .. file_info["remoteName"]))
      file:close()
    end

    os.remove(file)
    os.remove(patch)

    os.rename(output, file)
  end

  os.remove(game_path .. "/hdifffiles.txt")
end

local function process_deletefiles()
  -- AnimeGame_Data/Plugins/metakeeper.dll
  for line in io.lines(game_path .. "/deletefiles.txt") do
    os.remove(game_path .. "/" .. line)
  end

  os.remove(game_path .. "/deletefiles.txt")
end

-- Get addon integrity info
function v1_addons_get_integrity_info(group_name, addon_name, addon_path, edition)
  -- There's no pkg_version per voiceover?
  return {}
end

-- Game update processing
function v1_game_diff_transition(game_path, edition)
  local file = io.open(game_path .. "/.version", "w+")
  local version = v1_game_get_version(game_path) or game_api(edition)["data"]["game"]["latest"]["version"]

  file:write(version)
  file:close()
end

-- Game update post-processing
function v1_game_diff_post_transition(game_path, edition)
  process_hdifffiles(game_path, edition)
  process_deletefiles(game_path, edition)
end

-- Addon update processing
function v1_addons_diff_transition(group_name, addon_name, addon_path, edition)
  local file = nil
  local version = nil

  if group_name == "voiceovers" then
    file = io.open(addon_path .. "/StarRail_Data/Persistent/Audio/AudioPackage/Windows/" .. get_voiceover_folder(addon_name) .. "/.version", "w+")
    version = v1_addons_get_version(group_name, addon_name, addon_path, edition) or game_api(edition)["data"]["game"]["latest"]["version"]
  elseif group_name == "extra" and addon_name == "jadeite" then
    file = io.open(addon_path .. "/.version", "w+")
    version = get_jadeite_metadata()["jadeite"]["version"]
  end

  if file ~= nil and version ~= nil then
    file:write(version)
    file:close()
  end
end

-- Addon update post-processing
function v1_addons_diff_post_transition(group_name, addon_name, addon_path, edition)
  if group_name == "voiceovers" then
    process_hdifffiles(game_path, edition)
    process_deletefiles(game_path, edition)
  end
end
