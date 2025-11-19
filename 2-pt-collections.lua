--[[
    Project: Title Collections View

    Adds a virtual “📚 Collections” folder to the Project: Title file browser.
    Inside it, all KOReader collections appear as folders; entering one lists
    the books from that collection so you can browse them like normal files.
]] --

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
    local CenterContainer = require("ui/widget/container/centercontainer")
    local HorizontalGroup = require("ui/widget/horizontalgroup")
    local HorizontalSpan = require("ui/widget/horizontalspan")
    local VerticalGroup = require("ui/widget/verticalgroup")
    local VerticalSpan = require("ui/widget/verticalspan")
    local OverlapGroup = require("ui/widget/overlapgroup")
    local Geom = require("ui/geometry")
    local Size = require("ui/size")
    local Blitbuffer = require("ffi/blitbuffer")
    local BookInfoManager = require("bookinfomanager")

    if FileChooser._pt_collections_view_patch_applied then
        return
    end
    FileChooser._pt_collections_view_patch_applied = true

    local COLLECTIONS_SYMBOL = "\u{272A}"
    local COLLECTIONS_SEGMENT = COLLECTIONS_SYMBOL .. " " .. _("Collections")
    local root_icon_path = DataStorage:getDataDir() .. "/icons/folder.collections.png"

    local SHOW_FAVORITES_COLLECTION = false

    local function get_single_icon_size(max_w, max_h)
        local border_size = Size.border.thin
        local w = max_w - (2 * border_size)
        local h = max_h - (2 * border_size)
        return w, h
    end

    local function get_stack_grid_size(max_w, max_h)
        local max_img_w = 0
        local max_img_h = 0
        if BookInfoManager:getSetting("use_stacked_foldercovers") then
            max_img_w = (max_w * 0.75) - (Size.border.thin * 2) - Size.padding.default
            max_img_h = (max_h * 0.75) - (Size.border.thin * 2) - Size.padding.default
        else
            max_img_w = (max_w - (Size.border.thin * 4) - Size.padding.small) / 2
            max_img_h = (max_h - (Size.border.thin * 4) - Size.padding.small) / 2
        end
        if max_img_w < 10 then max_img_w = max_w * 0.8 end
        if max_img_h < 10 then max_img_h = max_h * 0.8 end
        return max_img_w, max_img_h
    end

    local function create_blank_cover(width, height, background_idx)
        local backgrounds = {
            Blitbuffer.COLOR_LIGHT_GRAY,
            Blitbuffer.COLOR_GRAY_D,
            Blitbuffer.COLOR_GRAY_E,
        }
        local max_img_w = width - (Size.border.thin * 2)
        local max_img_h = height - (Size.border.thin * 2)
        return FrameContainer:new {
            width = width,
            height = height,
            radius = Size.radius.default,
            margin = 0,
            padding = 0,
            bordersize = Size.border.thin,
            color = Blitbuffer.COLOR_DARK_GRAY,
            background = backgrounds[background_idx],
            CenterContainer:new {
                dimen = Geom:new { w = max_img_w, h = max_img_h },
                HorizontalSpan:new { width = max_img_w, height = max_img_h },
            }
        }
    end

    local function build_diagonal_stack(images, max_w, max_h)
        local top_image_size = images[#images]:getSize()
        local nb_fakes = (4 - #images)
        for i = 1, nb_fakes do
            table.insert(images, 1, create_blank_cover(top_image_size.w, top_image_size.h, (i % 2 + 2)))
        end

        local stack_items = {}
        local stack_width = 0
        local stack_height = 0
        local inset_left = 0
        local inset_top = 0
        for _, img in ipairs(images) do
            local frame = FrameContainer:new {
                margin = 0,
                bordersize = 0,
                padding = nil,
                padding_left = inset_left,
                padding_top = inset_top,
                img,
            }
            stack_width = math.max(stack_width, frame:getSize().w)
            stack_height = math.max(stack_height, frame:getSize().h)
            inset_left = inset_left + (max_w * 0.08)
            inset_top = inset_top + (max_h * 0.08)
            table.insert(stack_items, frame)
        end

        local stack = OverlapGroup:new {
            dimen = Geom:new { w = stack_width, h = stack_height },
        }
        table.move(stack_items, 1, #stack_items, #stack + 1, stack)
        return CenterContainer:new {
            dimen = Geom:new { w = max_w, h = max_h },
            stack,
        }
    end

    local function build_grid(images, max_w, max_h)
        local row1 = HorizontalGroup:new {}
        local row2 = HorizontalGroup:new {}
        local layout = VerticalGroup:new {}

        if #images == 3 then
            local w3, h3 = images[3]:getSize().w, images[3]:getSize().h
            table.insert(images, 2, create_blank_cover(w3, h3, 3))
        elseif #images == 2 then
            local w1, h1 = images[1]:getSize().w, images[1]:getSize().h
            local w2, h2 = images[2]:getSize().w, images[2]:getSize().h
            table.insert(images, 2, create_blank_cover(w1, h1, 3))
            table.insert(images, 3, create_blank_cover(w2, h2, 2))
        elseif #images == 1 then
            local w1, h1 = images[1]:getSize().w, images[1]:getSize().h
            table.insert(images, 1, create_blank_cover(w1, h1, 3))
            table.insert(images, 2, create_blank_cover(w1, h1, 2))
            table.insert(images, 4, create_blank_cover(w1, h1, 3))
        end

        for i, img in ipairs(images) do
            if i < 3 then
                table.insert(row1, img)
            else
                table.insert(row2, img)
            end
            if i == 1 then
                table.insert(row1, HorizontalSpan:new { width = Size.padding.small })
            elseif i == 3 then
                table.insert(row2, HorizontalSpan:new { width = Size.padding.small })
            end
        end

        table.insert(layout, row1)
        table.insert(layout, VerticalSpan:new { width = Size.padding.small })
        table.insert(layout, row2)
        return layout
    end

    local function get_collection_cover_widgets(max_w, max_h, specific_collection_name)
        local covers = {}
        local max_img_w, max_img_h = get_stack_grid_size(max_w, max_h)

        local candidates = {}

        if specific_collection_name then
            local coll = ReadCollection.coll[specific_collection_name]
            if coll then
                for _, book in pairs(coll) do
                    if book.file then table.insert(candidates, book.file) end
                end
            end
        else
            for _, coll in pairs(ReadCollection.coll) do
                for _, book in pairs(coll) do
                    if book.file then table.insert(candidates, book.file) end
                end
            end
        end

        while #covers < 4 and #candidates > 0 do
            local rand_idx = math.random(1, #candidates)
            local fullpath = candidates[rand_idx]
            table.remove(candidates, rand_idx)

            if fullpath and util.fileExists(fullpath) then
                local bookinfo = BookInfoManager:getBookInfo(fullpath, true)
                if bookinfo and bookinfo.cover_bb then
                    local border_total = (Size.border.thin * 2)
                    local _, _, scale_factor = BookInfoManager.getCachedCoverSize(
                        bookinfo.cover_w, bookinfo.cover_h, max_img_w, max_img_h)

                    local wimage = ImageWidget:new {
                        image = bookinfo.cover_bb,
                        scale_factor = scale_factor,
                    }

                    table.insert(covers, FrameContainer:new {
                        width = math.floor((bookinfo.cover_w * scale_factor) + border_total),
                        height = math.floor((bookinfo.cover_h * scale_factor) + border_total),
                        margin = 0,
                        padding = 0,
                        radius = Size.radius.default,
                        bordersize = Size.border.thin,
                        color = Blitbuffer.COLOR_GRAY_3,
                        background = Blitbuffer.COLOR_GRAY_3,
                        wimage,
                    })
                end
            end
        end
        return covers
    end

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
        if not base or base == "" then return segment end
        if base:sub(-1) == "/" then return base .. segment end
        return base .. "/" .. segment
    end

    local function normalizeVirtualPath(path)
        if not path or path == "" then return path end
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
        return normalizeVirtualPath((G_reader_settings and G_reader_settings:readSetting("home_dir")) or
            filemanagerutil.getDefaultDir())
    end

    local function isHomePath(path)
        if not path then return false end
        local normalized_path = normalizeVirtualPath(path)
        local home_dir = getHomeDir()
        if normalized_path == home_dir then return true end
        local real_path = ffiUtil.realpath(path)
        if real_path then
            local normalized_real = normalizeVirtualPath(real_path)
            if normalized_real == home_dir then return true end
        end
        return false
    end

    local function isCollectionsRoot(path)
        return path and path:match("/" .. COLLECTIONS_SEGMENT_PATTERN .. "$")
    end

    local function getCollectionFromPath(path)
        if not path then return nil end
        local encoded = path:match("/" .. COLLECTIONS_SEGMENT_PATTERN .. "/(.+)$")
        if encoded then return decodeSegment(encoded) end
        return nil
    end

    local function containsCollectionsSegment(path)
        return path and path:find("/" .. COLLECTIONS_SEGMENT_PATTERN)
    end

    local function buildCollectionDirItems(self, path)
        local dirs = {}
        local collate = self:getCollate()
        for name, coll in pairs(ReadCollection.coll) do
            if not SHOW_FAVORITES_COLLECTION and name:lower() == ReadCollection.default_collection_name:lower() then
                goto continue
            end
            local count = util.tableSize(coll)
            local display = string.format("%s (%d)", name, count)
            local fake_attributes = { mode = "directory", size = count, modification = 0 }
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
        if not collection then return files end
        local ordered = {}
        for _, entry in pairs(collection) do table.insert(ordered, entry) end
        table.sort(ordered, function(a, b) return (a.order or 0) < (b.order or 0) end)
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
        if self.name ~= "filemanager" then return orig_genItemTableFromPath(self, path) end
        if isCollectionsRoot(path) then
            local dirs = buildCollectionDirItems(self, path)
            if #dirs == 0 then
                local collate = self:getCollate()
                local empty_item = self:getListItem(nil, _("No collections yet"), appendPath(path, "."),
                    { mode = "directory" }, collate)
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
        if not current_path then return orig_genItemTable(self, dirs, files, path) end
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
            local fake_attributes = { mode = "directory", size = visible_collections_count, modification = 0 }
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
                    idx = i; break
                end
            end
            if idx then
                local entry = table.remove(item_table, idx)
                local insert_pos = 1
                if item_table[1] and item_table[1].is_go_up then insert_pos = 2 end
                table.insert(item_table, insert_pos, entry)
            end
        end
        return item_table
    end

    if not ptutil._collections_icon_patch_applied then
        ptutil._collections_icon_patch_applied = true
        local orig_getFolderCover = ptutil.getFolderCover

        ptutil.getFolderCover = function(filepath, max_img_w, max_img_h)
            if filepath and filepath:find("/" .. COLLECTIONS_SEGMENT_PATTERN) then
                local found_icon = nil
                local is_png = false

                if isCollectionsRoot(filepath) then
                    if util.fileExists(root_icon_path) then
                        found_icon = root_icon_path
                        is_png = true
                    end
                else
                    local coll_name = getCollectionFromPath(filepath)
                    if coll_name then
                        local svg_path = DataStorage:getDataDir() .. "/icons/" .. coll_name .. ".folder.svg"
                        local png_path = DataStorage:getDataDir() .. "/icons/" .. coll_name .. ".folder.png"

                        if util.fileExists(svg_path) then
                            found_icon = svg_path
                            is_png = false
                        elseif util.fileExists(png_path) then
                            found_icon = png_path
                            is_png = true
                        end
                    end
                end

                if found_icon then
                    local w, h = get_single_icon_size(max_img_w, max_img_h)

                    local icon_widget = ImageWidget:new {
                        file = found_icon,
                        alpha = true,
                        width = w,
                        height = h,
                        resize = is_png,
                        scale_factor = is_png and nil or 0,
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

                local coll_name_for_stack = getCollectionFromPath(filepath)
                local images = get_collection_cover_widgets(max_img_w, max_img_h, coll_name_for_stack)

                if #images > 0 then
                    if BookInfoManager:getSetting("use_stacked_foldercovers") then
                        return build_diagonal_stack(images, max_img_w, max_img_h)
                    else
                        return build_grid(images, max_img_w, max_img_h)
                    end
                end
            end
            return orig_getFolderCover(filepath, max_img_w, max_img_h)
        end
    end

    local orig_changeToPath = FileChooser.changeToPath
    function FileChooser:changeToPath(path, focused_path)
        if self.name == "filemanager" and containsCollectionsSegment(path) then
            path = normalizeVirtualPath(path)
            if path == "" then path = "/" end
            self.path = path
            if focused_path then self.focused_path = focused_path end
            self:refreshPath()
            return
        end
        return orig_changeToPath(self, path, focused_path)
    end

    logger.info("Project: Title collections view patch applied")
end

userpatch.registerPatchPluginFunc("coverbrowser", patchProjectTitleCollections)
