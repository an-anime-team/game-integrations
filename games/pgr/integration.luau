type Variant = {
	platform: string,
	edition: string,
}

type Api = {
	-- can't use Semver for now because the version is major.minor.patch.wtf ??? example: 2.17.0.0
	version: string,
	-- need to change that by a list of CDN and not just one for download speed, but for fast testing I will just put the first one
	cdn_url: string,
	resources_base_path: string,
	resources: string,
}

type Resources = {
	resource_list: { Resource },
}

type Resource = {
	url: string,
	md5: string,
	download_size: number,
	destination: string,
}

local data_path = path.persist_dir("pgr")
local game_path = path.join(data_path, "resources")
local version_file_path = path.join(game_path, "version.json")

local function get_game_version(): string?
  dbg("Starting getting game version")
  if not fs.exists(version_file_path) then
    dbg("No game version found")
    return nil
  end

  dbg("Starting reading version file")

  local version_content = fs.read_file(version_file_path)

  dbg("Starting parsing version file")

  for version in version_content:gmatch("^{package_version:([0-9]*.[0-9]*.[0-9]*)}$") do
    dbg("Got game version")
    return version
  end

  dbg("No game version")

  return nil
end

local function fetch_api(): Api
  local iter = import("iterable")

  dbg("before fetching request")
	local response = net.fetch("https://prod-alicdn-gamestarter.kurogame.com/pcstarter/prod/game/G143/4/index.json")

  dbg("Got API response")

	if not response.is_ok then
		error("Failed to get CDN list: HTTP code " .. response.status)
	end

  dbg("Starting parsing API response")

	local api = str.decode(str.from_bytes(response.body), "json")

  dbg("JSON successfully parsed : ", api)

	local api: Api = {
		version = api.default.version,
		cdn_url = iter(clone(api.default.cdnList)).first().url,
		resources_base_path = api.default.resourcesBasePath,
		resources = api.default.resources,
	}

  dbg("API Type :", api)

	return api
end

local function fetch_resources(api: Api): Resources
  local iter = import("iterable")

  dbg("Using this api to fetch the game resources : ", api)

  local resources_url = api.cdn_url .. api.resources

  dbg("Starting to fetch game resources -> " .. resources_url)

	local response = net.fetch(resources_url)

	if not response.is_ok then
		error("Failed to get resources: HTTP code " .. response.status)
	end

  dbg("Got game resouces")

	local info = str.decode(str.from_bytes(response.body), "json")

  dbg("Decoded body")
  dbg("Starting parsing body")

	local resources: Resources = {
		resource_list = iter(info.resource).map(function(segment): Resource
			return {
				url = api.cdn_url .. api.resources_base_path .. segment.dest,
				destination = segment.dest,
				md5 = segment.md5,
				download_size = segment.size,
			}
		end).collect(),
	}

  dbg("Got resource")

	return resources
end

local function delete_game_resource()
	pcall(fs.remove_dir, game_path)
end

return {
	standard = 1,

	editions = function(platform: string)
		return {
			{
				name = "global",
				title = {
					en = "Global",
					ru = "Глобальная",
					fr = "Global",
				},
			},
		}
	end,

	game = {
		get_status = function(variant: Variant)
      if not get_game_version() then
        return "not-installed"
      end

			return "installed"
		end,

		get_diff = function(variant: Variant)
      local i18n = import("i18n").i18n

			return {
				title = i18n("install_game"),

				pipeline = {
          {
						title = i18n("deletet"),

						description = i18n("delete_old_files"),

						perform = function(progress)
							--delete_game_resource()
						end,
					},
					{
						title = i18n("download"),

						description = i18n("download_game_file"),

						perform = function(updater)
							local api = fetch_api()
							local resources = fetch_resources(api)

							local total_size = 0
							local current_size = 0

              dbg("Calculating total download size")

							for _, resource in resources.resource_list do
								total_size = total_size + resource.download_size
							end

              dbg("Start downloading resources...")

							for _, resource in resources.resource_list do
                local destination = game_path .. resource.destination

                dbg("Downloading -> " .. destination)
                dbg("From -> " .. resource.url)

                --if not fs.exists(path.parent(destination)) then
                --  dbg("Parent directory not created, creating it...")
                --  fs.create_dir(path.parent(destination))
                --end

                if fs.exists(destination) then
                  dbg("file already existing, challenging it...")

                  local hasher = hash.builder("md5")
                  local file_content = fs.read(destination)
                  hash.write(hasher, file_content)
                  local hash_result = str.encode(hash.finalize(hasher), "hex")
                  dbg("Resource md5 hash -> " .. resource.md5)
                  dbg("Md5 hash found -> " .. hash_result)

                  if not hash_result == resource.md5 then
                    dbg("Hashes are not the same, the file may be currupted or comprised, deleting it...")
                    fs.remove(destination)
                  end
                end

                local resouce_size = 0

								downloader.download(resource.url, {
									output_file = destination,
									continue_downloading = true,

									progress = function(current, total, diff)
                    local i18n = import("i18n").i18n

										updater({
											progress = {
												current = current_size + current,
												total = total_size,

												format = function()
													local current = (current_size + current) / 1000 / 1000 / 1000
													local total = total_size / 1000 / 1000 / 1000

                          --dbg("Downloaded " .. current .. " GB / " .. total .. " GB")

													return i18n("downloading_progress", {
                            current = math.floor(current * 100) / 100,
													  total = math.floor(total * 100) / 100
                          })
												end,
											},
										})

                    resource_size = total
									end,
								})

                current_size = current_size + resource_size
							end
						end,
					},
				},
			}
		end,

		get_launch_info = function(variant: Variant)
			return {
				status = "disabled",
				hint = {
					en = "WIP implementation used for testing",
					ru = "Это тестовая реализация, не предназначенная для реального использования",
					ru = "WIP implémentation utilisée pour faire des tests",
				},
				binary = "",
			}
		end,
	},

	settings = {
		get_property = function(name: string)
			return nil
		end,

		set_property = function(name: string, value: any) end,

		get_layout = function(variant: Variant)
			return {}
		end,
	},
}
