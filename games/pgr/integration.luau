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
  if not fs.exists(version_file_path) then
    return nil
  end

  local version_content = fs.read_file(version_file_path)

  for version in version_content:gmatch("^{package_version:([0-9]*.[0-9]*.[0-9]*)}$") do
    return version
  end

  return nil
end

local function fetch_api(): Api
	local response = net.fetch("https://prod-alicdn-gamestarter.kurogame.com/pcstarter/prod/game/G143/4/index.json")

  dbg("Got API response", response)

	if not response.is_ok then
		error("Failed to get CDN list: HTTP code " .. response.status)
	end

	local api = str.decode(str.from_bytes(response.body), "json")

	local api: Api = {
		version = api.default.version,
		cdn_url = iter(clone(api.default.cdnList)).first(),
		resources_base_path = api.default.resourcesBasePath,
		resources = api.default.resources,
	}

	return api
end

local function fetch_resources(api: Api): Resources
	local response = net.fetch(api.cdn_url .. api.resources_path)

	if not response.is_ok then
		error("Failed to get resources: HTTP code " .. response.status)
	end

	local info = str.decode(str.from_bytes(response.body), "json")

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
			return {
				title = {
					en = "Install game",
					fr = "Installer le jeu",
				},

				pipeline = {
					{
						title = {
							en = "Delete",
							fr = "Supprimer",
						},

						description = {
							en = "Clean the game directory",
							fr = "Nettoyer le dossier du jeu",
						},

						perform = function(progress)
							delete_game_resource()
						end,
					},
					{
						title = {
							en = "Download",
							fr = "Téléchargement",
						},

						description = {
							en = "Download game resources",
							fr = "Téléchargement des resources du jeu",
						},

						perform = function(updater)
							local api = fetch_api()
							local resources = fetch_resources(api)
							local total_size = 0
							local current_size = 0

							for _, resource in resources.resource_list do
								total_size = total_size + resource.download_size
							end

							for _, resource in resources.resource_list do
								downloader.download(resource.url, {
									output_file = game_path .. resource.destination,
									continue_downloading = false,

									progress = function(current, total, diff)
										updater({
											progress = {
												current = current_size + current,
												total = total_size,

												format = function()
													local current = current / 1000 / 1000 / 1000
													local total = total / 1000 / 1000 / 1000

													current = math.floor(current * 100) / 100
													total = math.floor(total * 100) / 100

													return {
														en = `Downloaded {current} GB / {total} GB`,
														ru = `Скачано {current} ГБ / {total} ГБ`,
														fr = `Télécharger {current} GB / {total} GB`,
													}
												end,
											},
										})
									end,
								})
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
