-- lua-proton v0.1.0
-- Copyright (C) 2026 Nikita Podvirnyi <krypt0nn@vk.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy
-- of this software and associated documentation files (the “Software”), to deal
-- in the Software without restriction, including without limitation the rights
-- to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
-- copies of the Software, and to permit persons to whom the Software is
-- furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in
-- all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
-- THE SOFTWARE.

if not import then
    -- polyfill: old agl-runtime versions don't have `import` function
    function import(name: string)
        local resource = load(name)

        if resource.format ~= "package" then
            return resource.value
        end

        local outputs = {}

        for name, value in pairs(resource.value) do
            outputs[name] = value.value
        end

        return outputs
    end
end

local data_dir_path: string = path.persist_dir("lua-proton")

local versions_dir_path: string = path.join(data_dir_path, "versions")
local prefixes_dir_path: string = path.join(data_dir_path, "prefixes")
local umu_launcher_path: string = path.join(data_dir_path, "umu-run")

local __i18n = nil

local function i18n(...)
    if not __i18n then
        local locales = import("locales-src")

        locales = fs.read_file(locales):await()
        locales = str.decode("toml", str.from_bytes(locales))

        __i18n = import("i18n").i18n(locales)
    end

    return (__i18n)(...)
end

type ProtonVersion = {
    -- Unique identifier of the proton version.
    name: string,

    -- Proton version title.
    title: string,

    -- URL to download tarball with this version from.
    url: string,

    -- Blake3 hash of the downloaded version tarball.
    hash: string?
}

type ProtonVersionsGroup = {
    -- Unique identifier of the proton versions group.
    name: string,

    -- Versions group title.
    title: string,

    -- List of proton version that belong to this group.
    versions: {ProtonVersion}
}

local __versions = {}

-- Register proton versions group and all the stored version in the library.
local function proton_register_versions(group: ProtonVersionsGroup)
    if not group.name or not group.versions then
        return
    end

    if not __versions[group.name] then
        __versions[group.name] = {
            versions = {}
        }
    end

    __versions[group.name].title = group.title or group.name

    if typeof(group.versions) == "table" then
        for _, version in ipairs(group.versions) do
            if version.name and typeof(version.name) == "string"
                and version.url and typeof(version.url) == "string"
            then
                __versions[group.name].versions[version.name] = {
                    title = version.title or version.name,
                    url = version.url,
                    hash = if not version.hash or version.hash == "" then nil else version.hash
                }
            end
        end
    end
end

-- List all available proton versions.
local function proton_list_available_versions(): {ProtonVersionsGroup}
    local versions: {ProtonVersionsGroup} = {}

    for group_name, group in pairs(__versions) do
        local group_versions: {ProtonVersion} = {}

        for version_name, version in pairs(group.versions) do
            table.insert(group_versions, {
                name = version_name,
                title = version.title or version_name,
                url = version.url,
                hash = version.hash
            })
        end

        table.insert(versions, {
            name = group_name,
            title = group.title or group_name,
            versions = group_versions
        })
    end

    return versions
end

-- Read all the proton versions stored in the versions directory.
local function proton_list_downloaded_versions(): {ProtonVersionsGroup}
    local versions: {ProtonVersionsGroup} = {}

    if not fs.exists(versions_dir_path) then
        return versions
    end

    for _, entry in pairs(fs.read_dir(versions_dir_path):await()) do
        if entry.type == "directory" then
            local found = false

            for group_name, group in pairs(__versions) do
                for version_name, version in pairs(group.versions) do
                    if entry.name == version_name then
                        local group_index = nil

                        for i, group in ipairs(versions) do
                            if group.name == group_name then
                                group_index = i

                                break
                            end
                        end

                        if not group_index then
                            table.insert(versions, {
                                name = group_name,
                                title = group.title or group_name,
                                versions = {}
                            })

                            group_index = #versions
                        end

                        table.insert(versions[group_index].versions, {
                            name = version_name,
                            title = version.title or version_name,
                            url = version.url,
                            hash = version.hash
                        })

                        found = true

                        break
                    end
                end

                if found then
                    break
                end
            end
        end
    end

    return versions
end

-- Check if a proton version with given name is downloaded.
local function proton_version_is_downloaded(name: string): boolean
    return fs.exists(path.join(versions_dir_path, name, "files", "bin", "wine"))
end

-- Try to get information about selected proton version.
local function proton_version_get_info(name: string, group_name: string?): ProtonVersion?
    local version = nil

    if group_name and __versions[group_name] then
        version = clone(__versions[group_name].versions[name])
    else
        for _, group in pairs(__versions) do
            if group.versions[name] then
                version = clone(group.versions[name])

                break
            end
        end
    end

    if not version then
        return nil
    end

    return {
        name = name,
        title = version.title,
        url = version.url,
        hash = version.hash
    }
end

type Options = {
    proton: {
        -- Whether or not to use default proton versions provided by the
        -- library. Default is true.
        use_base_versions: boolean?,

        -- List of additional proton versions.
        extra_versions: {ProtonVersionsGroup}?
    }?,

    umu_launcher: {
        -- Path to the umu-run binary. If unset, then default path is used.
        binary_path: string?,

        -- umu-launcher game identifier.
        game_id: string?
    }?,

    prefix: {
        -- Name of the proton prefix folder. If unset, then umu-launcher's game
        -- identifier will be used. If it's unset too, then "common" will be
        -- used.
        name: string?
    }?,

    settings: {
        -- Proton settings getter. If unset, only default settings values will
        -- be used.
        get_property: ((name: string) -> any)?,

        -- Proton settings setter. If unset, settings changes will never be
        -- saved.
        set_property: ((name: string, value: any) -> ())?
    }?
}

return function(options: Options?)
    -- Register base proton versions.
    if not options or not options.proton or
        (options.proton.use_base_versions == nil or options.proton.use_base_versions == true)
    then
        for _, name in ipairs({ "dwproton-src" }) do
            local versions = import(name)

            if versions then
                versions = fs.read_file(versions):await()
                versions = str.decode("json", str.from_bytes(versions))

                proton_register_versions(versions)
            end
        end
    end

    -- Register extra proton versions.
    if options and options.proton and options.proton.extra_versions then
        for _, group in ipairs(options.proton.extra_versions) do
            proton_register_versions(group)
        end
    end

    -- Prepare sanitized settings getter and setter.
    local __settings = {}

    local function settings_get_property(name: string): any
        if options and options.settings and options.settings.get_property then
            return options.settings.get_property(name)
        else
            return clone(__settings[name])
        end
    end

    local function settings_set_property(name: string, value: any)
        if options and options.settings and options.settings.set_property then
            options.settings.set_property(name, value)
        else
            __settings[name] = value
        end
    end

    -- Validate selected proton group and version names.
    local selected_proton_group_name = settings_get_property("proton_group_name")
    local selected_proton_version_name = settings_get_property("proton_version_name")

    if not selected_proton_group_name or not selected_proton_version_name
        or (selected_proton_group_name and not __versions[selected_proton_group_name])
        or (selected_proton_group_name and __versions[selected_proton_group_name] and not __versions[selected_proton_group_name].versions[selected_proton_version_name])
    then
        for group_name, group in pairs(__versions) do
            selected_proton_group_name = group_name

            for version_name, _ in pairs(group.versions) do
                selected_proton_version_name = version_name

                break
            end

            break
        end

        settings_set_property("proton_group_name", selected_proton_group_name)
        settings_set_property("proton_version_name", selected_proton_version_name)
    end

    -- Import umu-launcher.
    local umu_launcher = import("umu-launcher")(
        if options and options.umu_launcher and options.umu_launcher.binary_path
            then options.umu_launcher.binary_path
            else umu_launcher_path
    )

    -- Check for missing dependencies.
    local _, umu_status = umu_launcher.umu.verify()

    if umu_status == "missing_bwrap_binary" then
        portal.toast({ message = i18n("umu_launcher_missing_python3") })
    elseif umu_status == "missing_python3_binary" then
        portal.toast({ message = i18n("umu_launcher_missing_bwrap") })
    end

    return {
        proton = {
            register_versions = proton_register_versions,
            list_available_versions = proton_list_available_versions,
            list_downloaded_versions = proton_list_downloaded_versions,
            is_version_downloaded = proton_version_is_downloaded,
            get_version_info = proton_version_get_info
        },

        game = {
            get_actions_pipeline = function(): any
                local actions = {}

                -- If umu-launcher is not installed.
                -- Ignore error status messages, we're respecting hash mismatch
                -- only.
                local umu_available, umu_status = umu_launcher.umu.verify()

                if not umu_available and umu_status == "invalid_hash" then
                    table.insert(actions, {
                        title = i18n("install_umu_launcher_title"),
                        perform = function(updater)
                            if fs.exists(umu_launcher.umu.path) then
                                fs.remove(umu_launcher.umu.path):await()
                            end

                            umu_launcher.umu.install(function(current: number, total: number, action: "download" | "extract")
                                updater({
                                    current = current,
                                    total = total,
                                    format = function()
                                        local current: string = string.format("%.2f", current / 1024)
                                        local total: string = string.format("%.2f", total / 1024)

                                        if action == "download" then
                                            return i18n("downloading_progress_kb", {
                                                current = current,
                                                total = total
                                            })
                                        elseif action == "extract" then
                                            return i18n("extracting_progress_kb", {
                                                current = current,
                                                total = total
                                            })
                                        else
                                            return i18n("processing_progress_kb", {
                                                current = current,
                                                total = total
                                            })
                                        end
                                    end
                                })
                            end)
                        end
                    })
                end

                -- If selected proton version is not installed.
                local proton_version_name = settings_get_property("proton_version_name")
                local proton_version_info = proton_version_get_info(proton_version_name)

                if proton_version_info and not proton_version_is_downloaded(proton_version_name) then
                    local proton_tarball_path: string = path.join(
                        path.temp_dir(),
                        path.file_name(proton_version_info.url)
                    )

                    table.insert(actions, {
                        title = i18n("download_proton_version_title", {
                            title = proton_version_info.title
                        }),

                        perform = function(updater)
                            local downloader_handle = downloader.create()

                            local task_handle = downloader.download(downloader_handle, {
                                url = proton_version_info.url,
                                output_file = proton_tarball_path,
                                continue_download = true,

                                on_update = function(current: number, total: number)
                                    updater({
                                        current = current,
                                        total = total,
                                        format = function()
                                            local current: string = string.format("%.2f", current / 1024 / 1024)
                                            local total: string = string.format("%.2f", total / 1024 / 1024)

                                            return i18n("downloading_progress_mb", {
                                                current = current,
                                                total = total
                                            })
                                        end
                                    })
                                end
                            })

                            downloader.wait(task_handle)
                            downloader.close(downloader_handle)
                        end
                    })

                    -- Verify downloaded proton version tarball only if we know
                    -- its expected hash.
                    if proton_version_info.hash then
                        table.insert(actions, {
                            title = i18n("verify_proton_version_title", {
                                title = proton_version_info.title
                            }),

                            perform = function()
                                local tarball_hash = hash.digitize_file("blake3", proton_tarball_path):await()

                                if str.encode("hex", tarball_hash) ~= proton_version_info.hash then
                                    dbg("lua-proton: downloaded proton version has different hash", proton_version_info)

                                    fs.remove_file(proton_tarball_path):await()
                                end
                            end
                        })
                    end

                    table.insert(actions, {
                        title = i18n("extract_proton_version_title", {
                            title = proton_version_info.title
                        }),

                        before = function()
                            return fs.exists(proton_tarball_path)
                        end,

                        perform = function(updater)
                            local archive_handle = archive.open(proton_tarball_path)

                            archive.extract(
                                archive_handle,
                                versions_dir_path,
                                function(current: number, total: number)
                                    updater({
                                        current = current,
                                        total = total,
                                        format = function()
                                            local current: string = string.format("%.2f", current / 1024 / 1024)
                                            local total: string = string.format("%.2f", total / 1024 / 1024)

                                            return i18n("extracting_progress_mb", {
                                                current = current,
                                                total = total
                                            })
                                        end
                                    })
                                end
                            )

                            archive.close(archive_handle)

                            fs.remove_file(proton_tarball_path):await()
                        end
                    })
                end

                -- If proton prefix is not available.
                local proton_version_path: string = path.join(
                    versions_dir_path,
                    proton_version_name
                )

                local proton_prefix_dir_path: string = path.join(
                    prefixes_dir_path,

                    if options and options.prefix and options.prefix.name
                        then options.prefix.name
                    elseif options and options.umu_launcher and options.umu_launcher.game_id
                        then options.umu_launcher.game_id
                    else "common"
                )

                if not umu_launcher.prefix.verify(proton_prefix_dir_path) then
                    table.insert(actions, {
                        title = i18n("create_proton_prefix_title"),

                        perform = function(updater)
                            pcall(
                                umu_launcher.prefix.create,
                                proton_version_path,
                                proton_prefix_dir_path
                            )
                        end
                    })
                end

                if #actions == 0 then
                    return nil
                else
                    return {
                        title = i18n("update_proton_title"),
                        pipeline = actions
                    }
                end
            end

            -- wrap_launch_info = function(launch_info)
            --     return launch_info
            -- end
        },

        settings = {
            get_property = settings_get_property,
            set_property = settings_set_property,

            get_layout = function(): any
                -- Prepare settings values.
                local proton_groups = {}
                local proton_versions = {}

                local selected_proton_group_name = settings_get_property("proton_group_name")
                local selected_proton_version_name = settings_get_property("proton_version_name")

                local available_proton_versions = proton_list_available_versions()

                local is_proton_group_name_valid = false

                -- Fill proton groups table.
                for _, group in ipairs(available_proton_versions) do
                    proton_groups[group.name] = group.title

                    -- If the group is not selected then select it.
                    if not selected_proton_group_name then
                        is_proton_group_name_valid = true

                        selected_proton_group_name = group.name
                        selected_proton_version_name = group.versions[1].name

                        settings_set_property("proton_group_name", selected_proton_group_name)
                        settings_set_property("proton_version_name", selected_proton_version_name)

                    -- If the group is selected and it matched the current one
                    -- then make the group name as valid.
                    elseif selected_proton_group_name == group.name then
                        is_proton_group_name_valid = true
                    end
                end

                -- If group name is invalid (we don't know group with such name)
                -- then replace it by the first available one.
                if not is_proton_group_name_valid then
                    selected_proton_group_name = available_proton_versions[1].name
                    selected_proton_version_name = available_proton_versions[1].versions[1].name

                    settings_set_property("proton_group_name", selected_proton_group_name)
                    settings_set_property("proton_version_name", selected_proton_version_name)
                end

                -- Validate proton version name and fill the versions table.
                for _, group in ipairs(available_proton_versions) do
                    if group.name == selected_proton_group_name then
                        local found = false

                        for _, version in ipairs(group.versions) do
                            proton_versions[version.name] = version.title

                            if version.name == selected_proton_version_name then
                                found = true
                            end
                        end

                        -- If there's no proton version with selected name then
                        -- replace it by the first available one.
                        if not found then
                            selected_proton_version_name = group.versions[1].name

                            settings_set_property("proton_version_name", selected_proton_version_name)
                        else
                            break
                        end
                    end
                end

                return {
                    {
                        title = i18n("settings_group_proton_title"),
                        entries = {
                            {
                                name = "proton_group_name",
                                title = i18n("settings_proton_group_name_title"),
                                reactivity = "release",
                                entry = {
                                    format = "enum",
                                    values = proton_groups,
                                    selected = selected_proton_group_name
                                }
                            },
                            {
                                name = "proton_version_name",
                                title = i18n("settings_proton_version_name_title"),
                                entry = {
                                    format = "enum",
                                    values = proton_versions,
                                    selected = selected_proton_version_name
                                }
                            }
                        } :: {any}
                    }
                }
            end
        }
    }
end
