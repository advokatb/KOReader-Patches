--[[
    Project: Title Collections View

    Adds a virtual “📚 Collections” folder to the Project: Title file browser.
    Inside it, all KOReader collections appear as folders; entering one lists
    the books from that collection so you can browse them like normal files.
]]--

local userpatch = require("userpatch")
local _ = require("gettext")

local function patchProjectTitleCollections()
    local FileChooser = require("ui/widget/filechooser")
    local ReadCollection = require("readcollection")
    local util = require("util")
    local logger = require("logger")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local DataStorage = require("datastorage")
    local ptutil = require("ptutil")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local ImageWidget = require("ui/widget/imagewidget")
    local ffiUtil = require("ffi/util")

    if FileChooser._pt_collections_view_patch_applied then
        return
    end
    FileChooser._pt_collections_view_patch_applied = true

    local COLLECTIONS_SYMBOL = "\u{272A}"
    local COLLECTIONS_SEGMENT = COLLECTIONS_SYMBOL .. " " .. _("Collections")
    local custom_icon_path = DataStorage:getDataDir() .. "/icons/folder.collections.svg"
    local custom_icon_exists = util.fileExists(custom_icon_path)
    
    -- Set to false to hide the built-in Favorites collection from the Collections view
    local SHOW_FAVORITES_COLLECTION = false

    local function escapePattern(str)
        return str:gsub("([^%w])", "%%%1")
    end

    local COLLECTIONS_SEGMENT_PATTERN = escapePattern(COLLECTIONS_SEGMENT)

    local function encodeSegment(name)
        return (name:gsub("/", "／"))
    end

    local function decodeSegment(segment)
        return (segment:gsub("／", "/"))
    end

    local function appendPath(base, segment)
        if not base or base == "" then
            return segment
        end
        if base:sub(-1) == "/" then
            return base .. segment
        end
        return base .. "/" .. segment
    end

    local function normalizeVirtualPath(path)
        if not path or path == "" then
            return path
        end
        -- Remove trailing slashes first (except for root "/")
        while path:len() > 1 and path:sub(-1) == "/" do
            path = path:sub(1, -2)
        end
        local leading_slash = path:sub(1, 1) == "/"
        local segments = {}
        for part in path:gmatch("[^/]+") do
            if part == ".." then
                table.remove(segments)
            elseif part ~= "." and part ~= "" then
                table.insert(segments, part)
            end
        end
        local result = table.concat(segments, "/")
        if leading_slash and result ~= "" then
            result = "/" .. result
        elseif leading_slash and result == "" then
            result = "/"
        end
        return result
    end

    local function getHomeDir()
        return normalizeVirtualPath((G_reader_settings and G_reader_settings:readSetting("home_dir")) or filemanagerutil.getDefaultDir())
    end

    local function isHomePath(path)
        if not path then return false end
        local normalized_path = normalizeVirtualPath(path)
        local home_dir = getHomeDir()
        -- Compare normalized paths (both should be normalized without trailing slashes)
        if normalized_path == home_dir then
            return true
        end
        -- Also check realpath resolution
        local real_path = ffiUtil.realpath(path)
        if real_path then
            local normalized_real = normalizeVirtualPath(real_path)
            if normalized_real == home_dir then
                return true
            end
        end
        return false
    end

    local function isCollectionsRoot(path)
        return path and path:match("/" .. COLLECTIONS_SEGMENT_PATTERN .. "$")
    end

    local function getCollectionFromPath(path)
        if not path then return nil end
        local encoded = path:match("/" .. COLLECTIONS_SEGMENT_PATTERN .. "/(.+)$")
        if encoded then
            return decodeSegment(encoded)
        end
        return nil
    end

    local function containsCollectionsSegment(path)
        return path and path:find("/" .. COLLECTIONS_SEGMENT_PATTERN)
    end

    local function buildCollectionDirItems(self, path)
        local dirs = {}
        local collate = self:getCollate()
        for name, coll in pairs(ReadCollection.coll) do
            -- Skip Favorites collection if disabled
            if not SHOW_FAVORITES_COLLECTION and name:lower() == ReadCollection.default_collection_name:lower() then
                goto continue
            end
            local count = util.tableSize(coll)
            local display = string.format("%s (%d)", name, count)
            local fake_attributes = {
                mode = "directory",
                size = count,
                modification = 0,
            }
            local item_path = appendPath(path, encodeSegment(name))
            local entry = self:getListItem(nil, display, item_path, fake_attributes, collate)
            entry.is_directory = true
            table.insert(dirs, entry)
            ::continue::
        end
        table.sort(dirs, function(a, b) return a.text:lower() < b.text:lower() end)
        return dirs
    end

    local function buildCollectionFileItems(self, path, collection_name)
        local files = {}
        local collection = ReadCollection.coll[collection_name]
        if not collection then
            return files
        end
        local ordered = {}
        for _, entry in pairs(collection) do
            table.insert(ordered, entry)
        end
        table.sort(ordered, function(a, b)
            return (a.order or 0) < (b.order or 0)
        end)
        local collate = self:getCollate()
        for _, entry in ipairs(ordered) do
            local attributes = entry.attr or { mode = "file" }
            local display = entry.text or entry.file:match("([^/]+)$") or entry.file
            local file_item = self:getListItem(path, display, entry.file, attributes, collate)
            file_item.is_file = true
            table.insert(files, file_item)
        end
        return files
    end

    local orig_genItemTableFromPath = FileChooser.genItemTableFromPath
    function FileChooser:genItemTableFromPath(path)
        if self.name ~= "filemanager" then
            return orig_genItemTableFromPath(self, path)
        end
        if isCollectionsRoot(path) then
            local dirs = buildCollectionDirItems(self, path)
            if #dirs == 0 then
                local collate = self:getCollate()
                local empty_item = self:getListItem(nil, _("No collections yet"), appendPath(path, "."), { mode = "directory" }, collate)
                empty_item.dim = true
                dirs = { empty_item }
            end
            return self:genItemTable(dirs, {}, path)
        end
        local collection_name = getCollectionFromPath(path)
        if collection_name then
            local files = buildCollectionFileItems(self, path, collection_name)
            return self:genItemTable({}, files, path)
        end
        return orig_genItemTableFromPath(self, path)
    end

    local function countVisibleCollections()
        local count = 0
        for name, _ in pairs(ReadCollection.coll) do
            if SHOW_FAVORITES_COLLECTION or name:lower() ~= ReadCollection.default_collection_name:lower() then
                count = count + 1
            end
        end
        return count
    end

    local orig_genItemTable = FileChooser.genItemTable
    function FileChooser:genItemTable(dirs, files, path)
        local current_path = path or self.path
        if not current_path then
            return orig_genItemTable(self, dirs, files, path)
        end
        local normalized_path = normalizeVirtualPath(current_path)
        local visible_collections_count = countVisibleCollections()
        local should_inject = self.name == "filemanager"
            and not containsCollectionsSegment(current_path)
            and visible_collections_count > 0
            and isHomePath(normalized_path)

        local virtual_path
        if should_inject then
            dirs = dirs or {}
            local collate = self:getCollate()
            local fake_attributes = {
                mode = "directory",
                size = visible_collections_count,
                modification = 0,
            }
            virtual_path = appendPath(current_path, COLLECTIONS_SEGMENT)
            local entry = self:getListItem(nil, COLLECTIONS_SEGMENT, virtual_path, fake_attributes, collate)
            entry.is_directory = true
            entry.is_pt_collections_entry = true
            table.insert(dirs, entry)
        end

        local item_table = orig_genItemTable(self, dirs, files, path)

        if should_inject and item_table then
            local idx
            for i, item in ipairs(item_table) do
                if item.path == virtual_path then
                    idx = i
                    break
                end
            end
            if idx then
                local entry = table.remove(item_table, idx)
                local insert_pos = 1
                if item_table[1] and item_table[1].is_go_up then
                    insert_pos = 2
                end
                table.insert(item_table, insert_pos, entry)
        end
        end

        return item_table
    end

    if custom_icon_exists and not ptutil._collections_icon_patch_applied then
        ptutil._collections_icon_patch_applied = true
        local orig_getFolderCover = ptutil.getFolderCover
        ptutil.getFolderCover = function(filepath, max_img_w, max_img_h)
            if filepath and filepath:find("/" .. COLLECTIONS_SEGMENT_PATTERN) then
                local icon_widget = ImageWidget:new {
                    file = custom_icon_path,
                    alpha = true,
                    width = max_img_w,
                    height = max_img_h,
                    scale_factor = 0,
                    center_x_ratio = 0.5,
                    center_y_ratio = 0.5,
                    original_in_nightmode = false,
                }
                return FrameContainer:new {
                    width = max_img_w,
                    height = max_img_h,
                    margin = 0,
                    padding = 0,
                    bordersize = 0,
                    icon_widget,
                }
            end
            return orig_getFolderCover(filepath, max_img_w, max_img_h)
        end
    end

    local orig_changeToPath = FileChooser.changeToPath
    function FileChooser:changeToPath(path, focused_path)
        if self.name == "filemanager" and containsCollectionsSegment(path) then
            path = normalizeVirtualPath(path)
            if path == "" then
                path = "/"
            end
            self.path = path
            if focused_path then
                self.focused_path = focused_path
            end
            self:refreshPath()
            return
        end
        return orig_changeToPath(self, path, focused_path)
    end

    logger.info("Project: Title collections view patch applied")
end

userpatch.registerPatchPluginFunc("coverbrowser", patchProjectTitleCollections)

