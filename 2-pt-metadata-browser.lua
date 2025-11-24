--[[
    Project: Title Metadata Browser

    Adds a virtual "📚 Metadata" folder to the Project: Title file browser.
    Inside it, folders for different metadata types (authors, series, genres, year, etc.)
    appear; entering one lists the metadata values, and selecting a value shows matching books.
    
    Database location:
    - Project: Title: DataStorage:getSettingsDir() .. "/PT_bookinfo_cache.sqlite3"
    - CoverBrowser: DataStorage:getSettingsDir() .. "/coverbrowser_bookinfo_cache.sqlite3"
    - Statistics: DataStorage:getSettingsDir() .. "/statistics.sqlite3"
    
    Database schema (bookinfo table):
    - directory, filename, title, authors, series, language, keywords, description, pages, etc.
    - Keywords field contains newline-separated values (genres, years, etc.)
    
    Based on:
    - patches/KOReader-advokatb-patches/2-pt-collections.lua (virtual folder structure)
    - patches/2-BrowseByMetadata.lua (metadata browsing functionality)
]]--

local userpatch = require("userpatch")
local _ = require("gettext")
local ffiUtil = require("ffi/util")
local util = require("util")
local T = ffiUtil.template

local function patchProjectTitleMetadataBrowser()
    local FileChooser = require("ui/widget/filechooser")
    local filemanagerutil = require("apps/filemanager/filemanagerutil")
    local DataStorage = require("datastorage")
    local ptutil = require("ptutil")
    local FrameContainer = require("ui/widget/container/framecontainer")
    local ImageWidget = require("ui/widget/imagewidget")
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
    local LuaSettings = require("luasettings")

    if FileChooser._pt_metadata_browser_patch_applied then
        return
    end
    FileChooser._pt_metadata_browser_patch_applied = true

    -- ============================================================================
    -- CONFIGURATION SETTINGS - Customize the patch behavior here
    -- ============================================================================
    
    --[[
        MAIN SETTINGS
    --]]
    
    -- Enable/disable the Metadata virtual folder entirely
    -- Set to false to completely disable the Metadata folder feature
    local CONFIG_ENABLE_METADATA_FOLDER = true
    
    --[[
        METADATA TYPES ENABLE/DISABLE
        Set to false to hide specific metadata types from the Metadata folder
    --]]
    local CONFIG_ENABLE_TITLE = true      -- Browse by book titles
    local CONFIG_ENABLE_AUTHOR = true     -- Browse by authors
    local CONFIG_ENABLE_SERIES = true     -- Browse by series
    local CONFIG_ENABLE_GENRES = true     -- Browse by genres (from keywords field)
    local CONFIG_ENABLE_YEAR = true       -- Browse by publication years (from keywords field)
    
    --[[
        FILTERING SETTINGS
        Minimum number of books required to show a genre/year in the list
        - Set to 1 to show all genres/years
        - Set to 2+ to filter out rare genres/years (only show if at least N books have it)
        - Useful for large libraries to reduce clutter
    --]]
    local CONFIG_MIN_BOOKS_FOR_GENRE = 1  -- Minimum books per genre to display
    local CONFIG_MIN_BOOKS_FOR_YEAR = 1   -- Minimum books per year to display
    
    --[[
        DEBUG SETTINGS
    --]]
    -- Enable debug logging (useful for troubleshooting)
    -- When enabled, logs detailed information about metadata processing
    local CONFIG_ENABLE_DEBUG_LOGGING = false
    
    --[[
        APPEARANCE SETTINGS
    --]]
    -- Metadata folder symbol (icon) and display name
    -- You can change the symbol to any Unicode character or emoji
    local CONFIG_METADATA_SYMBOL = "\u{e257}"  -- Default: metadata icon
    -- Alternative symbols you can use:
    -- "\u{1F4D6}" = 📖 (open book)
    -- "\u{1F4DA}" = 📚 (books)
    -- "\u{1F4C3}" = 📃 (page with curl)
    -- "\u{2696}" = ⚖ (scales/balance)
    
    local CONFIG_METADATA_NAME = _("Metadata")  -- Display name for the folder
    
    -- Icon paths for the Metadata folder (custom icons can be placed here)
    local root_icon_png_path = DataStorage:getDataDir() .. "/icons/folder.metadata.png"
    local root_icon_svg_path = DataStorage:getDataDir() .. "/icons/folder.metadata.svg"
    
    --[[
        SORTING SETTINGS
    --]]
    -- Custom order for metadata types (optional, nil = use default order)
    -- List the types in the order you want them to appear
    -- Available types: "TITLE", "AUTHOR", "SERIES", "GENRES", "YEAR"
    -- Example: {"AUTHOR", "SERIES", "GENRES", "YEAR", "TITLE"}
    local CONFIG_METADATA_ORDER = nil  -- nil = default order, or table with custom order
    
    --[[
        SEARCH SETTINGS
    --]]
    -- Case sensitivity for genre/year matching
    -- false = case-insensitive (default), true = case-sensitive
    local CONFIG_CASE_SENSITIVE_GENRES = false
    
    --[[
        DISPLAY SETTINGS
    --]]
    -- Show book count next to each metadata value
    -- When true, displays "(N)" next to each genre/year/author/etc. showing number of books
    local CONFIG_SHOW_BOOK_COUNT = false
    
    -- Filter empty/null values
    -- When true, hides metadata values that are empty, null, or just whitespace
    local CONFIG_HIDE_EMPTY_VALUES = true
    
    --[[
        CUSTOM SYMBOLS FOR METADATA TYPES
        Override default symbols for each metadata type
        Set to nil to use default symbol, or provide custom Unicode character/emoji
    --]]
    local CONFIG_TITLE_SYMBOL = nil      -- Default: "\u{f02d}"
    local CONFIG_AUTHOR_SYMBOL = nil     -- Default: "\u{f2c0}"
    local CONFIG_SERIES_SYMBOL = nil     -- Default: "\u{ecd7}"
    local CONFIG_GENRES_SYMBOL = nil     -- Default: "\u{f02c}"
    local CONFIG_YEAR_SYMBOL = nil       -- Default: "\u{f073}"
    
    --[[
        GENRE FILTERING SETTINGS
        Control which genres are shown/hidden
    --]]
    -- Whitelist: only show these genres (empty table = show all)
    -- Example: {"Fantasy", "Sci-Fi", "Mystery"}
    local CONFIG_GENRE_WHITELIST = {}
    
    -- Blacklist: hide these genres (empty table = hide none)
    -- Example: {"Unknown", "Misc", "Uncategorized"}
    local CONFIG_GENRE_BLACKLIST = {}
    
    -- ============================================================================
    -- END OF CONFIGURATION
    -- ============================================================================
    
    -- Early return if Metadata folder is disabled
    if not CONFIG_ENABLE_METADATA_FOLDER then
        return
    end

    -- Store config globally for access from closures
    METADATA_CONFIG = {
        ENABLE_DEBUG_LOGGING = CONFIG_ENABLE_DEBUG_LOGGING,
        MIN_BOOKS_FOR_GENRE = CONFIG_MIN_BOOKS_FOR_GENRE,
        MIN_BOOKS_FOR_YEAR = CONFIG_MIN_BOOKS_FOR_YEAR,
        CASE_SENSITIVE_GENRES = CONFIG_CASE_SENSITIVE_GENRES,
        HIDE_EMPTY_VALUES = CONFIG_HIDE_EMPTY_VALUES,
        SHOW_BOOK_COUNT = CONFIG_SHOW_BOOK_COUNT,
        GENRE_WHITELIST = CONFIG_GENRE_WHITELIST,
        GENRE_BLACKLIST = CONFIG_GENRE_BLACKLIST,
    }

    local METADATA_SYMBOL = CONFIG_METADATA_SYMBOL
    local METADATA_SEGMENT = METADATA_SYMBOL .. " " .. CONFIG_METADATA_NAME

    local METADATA_TYPES = {
        TITLE = {
            browse_text = _("Title"),
            filter_text = _("Title"),
            db_column = "title",
            symbol = CONFIG_TITLE_SYMBOL or "\u{f02d}",
        },
        AUTHOR = {
            browse_text = _("Author"),
            filter_text = _("Author"),
            db_column = "authors",
            symbol = CONFIG_AUTHOR_SYMBOL or "\u{f2c0}",
        },
        SERIES = {
            browse_text = _("Series"),
            filter_text = _("Series"),
            db_column = "series",
            symbol = CONFIG_SERIES_SYMBOL or "\u{ecd7}",
        },
        GENRES = {
            browse_text = _("Genres"),
            filter_text = _("Genres"),
            db_column = "genres",
            symbol = CONFIG_GENRES_SYMBOL or "\u{f02c}",
        },
        YEAR = {
            browse_text = _("Year"),
            filter_text = _("Year"),
            db_column = "year",
            symbol = CONFIG_YEAR_SYMBOL or "\u{f073}",
        },
    }

    local METADATA_TYPES_ORDERED = {}
    local enabled_types = {}
    
    if CONFIG_ENABLE_TITLE then enabled_types["TITLE"] = METADATA_TYPES.TITLE end
    if CONFIG_ENABLE_AUTHOR then enabled_types["AUTHOR"] = METADATA_TYPES.AUTHOR end
    if CONFIG_ENABLE_SERIES then enabled_types["SERIES"] = METADATA_TYPES.SERIES end
    if CONFIG_ENABLE_GENRES then enabled_types["GENRES"] = METADATA_TYPES.GENRES end
    if CONFIG_ENABLE_YEAR then enabled_types["YEAR"] = METADATA_TYPES.YEAR end
    
    if CONFIG_METADATA_ORDER and type(CONFIG_METADATA_ORDER) == "table" then
        for _, type_name in ipairs(CONFIG_METADATA_ORDER) do
            if enabled_types[type_name] then
                table.insert(METADATA_TYPES_ORDERED, enabled_types[type_name])
            end
        end
        for type_name, type_data in pairs(enabled_types) do
            local found = false
            for _, ordered_name in ipairs(CONFIG_METADATA_ORDER) do
                if ordered_name == type_name then
                    found = true
                    break
                end
            end
            if not found then
                table.insert(METADATA_TYPES_ORDERED, type_data)
            end
        end
    else
        if CONFIG_ENABLE_TITLE then
            table.insert(METADATA_TYPES_ORDERED, METADATA_TYPES.TITLE)
        end
        if CONFIG_ENABLE_AUTHOR then
            table.insert(METADATA_TYPES_ORDERED, METADATA_TYPES.AUTHOR)
        end
        if CONFIG_ENABLE_SERIES then
            table.insert(METADATA_TYPES_ORDERED, METADATA_TYPES.SERIES)
        end
        if CONFIG_ENABLE_GENRES then
            table.insert(METADATA_TYPES_ORDERED, METADATA_TYPES.GENRES)
        end
        if CONFIG_ENABLE_YEAR then
            table.insert(METADATA_TYPES_ORDERED, METADATA_TYPES.YEAR)
        end
    end

    local METADATA_SYMBOLS = {}
    for k, v in pairs(METADATA_TYPES) do
        METADATA_SYMBOLS[v.symbol] = v
    end

    local VIRTUAL_PATH_TYPE_ROOT = "VIRTUAL_PATH_TYPE_ROOT"
    local VIRTUAL_PATH_TYPE_META_VALUES_LIST = "VIRTUAL_PATH_TYPE_META_VALUES_LIST"
    local VIRTUAL_PATH_TYPE_MATCHING_FILES = "VIRTUAL_PATH_TYPE_MATCHING_FILES"

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

    local function get_metadata_cover_widgets(max_w, max_h, base_dir, filters, file_chooser)
        local covers = {}
        local max_img_w, max_img_h = get_stack_grid_size(max_w, max_h)
        local candidates = {}

        if file_chooser and file_chooser.ui and file_chooser.ui.coverbrowser then
            local matching_files = file_chooser.ui.coverbrowser:getMatchingFiles(base_dir, filters or {})
            for _, v in ipairs(matching_files) do
                local fullpath = v[1]
                if fullpath and util.fileExists(fullpath) then
                    table.insert(candidates, fullpath)
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

    local METADATA_SEGMENT_PATTERN = escapePattern(METADATA_SEGMENT)

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

    local function isMetadataRoot(path)
        return path and path:match("/" .. METADATA_SEGMENT_PATTERN .. "$")
    end

    local function containsMetadataSegment(path)
        return path and path:find("/" .. METADATA_SEGMENT_PATTERN)
    end

    function FileChooser:getMetadataPathType(path)
        path = path or self.path
        if not path then return end
        if path:find("/" .. METADATA_SEGMENT_PATTERN .. "$") then
            return VIRTUAL_PATH_TYPE_ROOT
        end
        if path:find("/" .. METADATA_SEGMENT_PATTERN .. "/") then
            local _, last_part = util.splitFilePathName(path)
            local symbol = METADATA_SYMBOLS[last_part]
            if symbol and symbol.db_column then
                return VIRTUAL_PATH_TYPE_META_VALUES_LIST
            end
            return VIRTUAL_PATH_TYPE_MATCHING_FILES
        end
    end

    function FileChooser:getMetadataVirtualList(path, collate)
        local dirs, files = {}, {}
        local base_dir, virtual_root, virtual_path = path:match("(.-)/(" .. METADATA_SEGMENT_PATTERN .. ")(.*)")
        if not virtual_root then
            return dirs, files
        end

        local fragments = {}
        for fragment in util.gsplit(virtual_path, "/") do
            table.insert(fragments, fragment)
        end

        if #fragments == 0 or fragments[#fragments] == METADATA_SYMBOL then
            local filtering = #fragments > 0
            if filtering then
                path = path:match("(.*)/.*")
            end

            for i, v in ipairs(METADATA_TYPES_ORDERED) do
                local item = true
                if collate then
                    local fake_attributes = {
                        mode = "directory",
                        modification = 0,
                        access = 0,
                        change = 0,
                        size = i,
                    }
                    item = self:getListItem(nil, v.symbol .. " " .. (filtering and v.filter_text or v.browse_text),
                        path .. "/" .. v.symbol, fake_attributes, collate)
                    item.mandatory = nil
                end
                table.insert(dirs, item)
            end
            return dirs, files
        end

        local meta_name
        local filters = {}
        local filters_seen = {}
        local cur_value
        while #fragments > 0 do
            local fragment = table.remove(fragments)
            local meta = METADATA_SYMBOLS[fragment]
            if meta then
                if meta ~= METADATA_TYPES.TITLE then
                    local db_meta_name = meta.db_column
                    if cur_value ~= nil then
                        local filter_name = db_meta_name
                        if db_meta_name == "genres" or db_meta_name == "year" then
                            filter_name = "keywords"
                        end
                        table.insert(filters, {filter_name, cur_value})
                        if not filters_seen[db_meta_name] then
                            filters_seen[db_meta_name] = {}
                        end
                        filters_seen[db_meta_name][cur_value] = true
                    else
                        meta_name = db_meta_name
                    end
                end
            else
                cur_value = fragment
                if cur_value == "\u{2205}" then
                    cur_value = false
                end
            end
        end

        if meta_name == "title" then
            meta_name = nil
        end

        if meta_name then
            if self.ui and self.ui.coverbrowser then
                local matching_values = self.ui.coverbrowser:getMatchingMetadataValues(base_dir, meta_name, filters)
                local CONFIG = METADATA_CONFIG or {}
                for i, v in ipairs(matching_values) do
                    local value = v[1]
                    local count = v[2] or 0
                    
                    if CONFIG.HIDE_EMPTY_VALUES then
                        if not value or value == "" or value == "\u{2205}" then
                            goto continue
                        end
                        local trimmed = value:match("^%s*(.-)%s*$")
                        if trimmed == "" then
                            goto continue
                        end
                    end
                    
                    if not filters_seen[meta_name] or not filters_seen[meta_name][value] then
                        local fake_attributes = {
                            mode = "directory",
                            modification = 0,
                            access = 0,
                            change = 0,
                            size = i,
                        }
                        local display_name = value or "\u{2205}"
                        if CONFIG.SHOW_BOOK_COUNT and count > 0 then
                            display_name = display_name .. " (" .. count .. ")"
                        end
                        local this_path = path .. "/" .. (value or "\u{2205}")
                        local item = self:getListItem(nil, display_name, this_path, fake_attributes, collate)
                        item.nb_sub_files = count
                        item.mandatory = self:getMenuItemMandatory(item)
                        table.insert(dirs, item)
                    end
                    ::continue::
                end
            end
        else
            if self.ui and self.ui.coverbrowser then
                local matching_files = self.ui.coverbrowser:getMatchingFiles(base_dir, filters)
                for i, v in ipairs(matching_files) do
                    local fullpath, f = unpack(v)
                    local lfs = require("libs/libkoreader-lfs")
                    local attributes = lfs.attributes(fullpath)
                    if attributes and attributes.mode == "file" and self:show_file(f, fullpath) then
                        local item = self:getListItem(path, f, fullpath, attributes, collate)
                        table.insert(files, item)
                    end
                end
            end
        end

        return dirs, files
    end

    local orig_genItemTableFromPath = FileChooser.genItemTableFromPath
    function FileChooser:genItemTableFromPath(path)
        if self.name ~= "filemanager" then return orig_genItemTableFromPath(self, path) end

        if self:getMetadataPathType(path) then
            local collate = self:getCollate()
            local dirs, files = self:getMetadataVirtualList(path, collate)
            return self:genItemTable(dirs, files, path)
        end

        return orig_genItemTableFromPath(self, path)
    end

    local function injectMetadataFolder(self, dirs, files, path, item_table)
        if #METADATA_TYPES_ORDERED == 0 then
            return item_table
        end
        
        local current_path = path or self.path
        if not current_path then
            return item_table
        end

        local normalized_path = normalizeVirtualPath(current_path)
        local is_in_metadata = containsMetadataSegment(current_path)
        local is_home = isHomePath(normalized_path)
        local should_inject = self.name == "filemanager"
            and not is_in_metadata
            and is_home

        if not should_inject then
            return item_table
        end

        local virtual_path = appendPath(current_path, METADATA_SEGMENT)
        local collate = self:getCollate()
        local fake_attributes = {
            mode = "directory",
            size = #METADATA_TYPES_ORDERED,
            modification = 0,
        }
        local entry = self:getListItem(nil, METADATA_SEGMENT, virtual_path, fake_attributes, collate)
        entry.is_directory = true
        entry.is_pt_metadata_entry = true

        local idx = nil
        for i, item in ipairs(item_table) do
            if item.path == virtual_path then
                idx = i
                break
            end
        end

        if idx then
            entry = table.remove(item_table, idx)
        end

        local insert_pos = 1
        if item_table[1] and item_table[1].is_go_up then
            insert_pos = 2
        end
        table.insert(item_table, insert_pos, entry)

        return item_table
    end

    local function wrapCoverMenuGenItemTable()
        local ok, CoverMenu = pcall(require, "covermenu")
        if ok and CoverMenu and CoverMenu.genItemTable then
            local orig_CoverMenu_genItemTable = CoverMenu.genItemTable
            CoverMenu.genItemTable = function(self, dirs, files, path)
                local item_table = orig_CoverMenu_genItemTable(self, dirs, files, path)
                return injectMetadataFolder(self, dirs, files, path, item_table)
            end
        end
    end

    local orig_genItemTable = FileChooser.genItemTable
    function FileChooser:genItemTable(dirs, files, path)
        local item_table = orig_genItemTable(self, dirs, files, path)

        local virtual_path_type = self:getMetadataPathType(path)
        local up_path = path:gsub("(/[^/]+)$", "")

        if item_table[1] and item_table[1].path:find("/..$") then
            item_table[1].path = virtual_path_type ~= nil and up_path or path .. "/.."
        end

        return injectMetadataFolder(self, dirs, files, path, item_table)
    end

    local UIManager = require("ui/uimanager")
    UIManager:nextTick(function()
        wrapCoverMenuGenItemTable()
    end)

    local orig_getMenuItemMandatory = FileChooser.getMenuItemMandatory
    function FileChooser:getMenuItemMandatory(item, collate)
        if item.nb_sub_files then
            return T("%1 \u{F016}", item.nb_sub_files)
        end
        return orig_getMenuItemMandatory(self, item, collate)
    end

    if not ptutil._metadata_icon_patch_applied then
        ptutil._metadata_icon_patch_applied = true
        local orig_getFolderCover = ptutil.getFolderCover

        ptutil.getFolderCover = function(filepath, max_img_w, max_img_h)
            if filepath and filepath:find("/" .. METADATA_SEGMENT_PATTERN) then
                local found_icon = nil
                local is_png = false

                if isMetadataRoot(filepath) then
                    if util.fileExists(root_icon_svg_path) then
                        found_icon = root_icon_svg_path
                        is_png = false
                    elseif util.fileExists(root_icon_png_path) then
                        found_icon = root_icon_png_path
                        is_png = true
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

                local base_dir, _, virtual_path = filepath:match("(.-)/(" .. METADATA_SEGMENT_PATTERN .. ")(.*)")
                if base_dir and virtual_path then
                    local fragments = {}
                    for fragment in util.gsplit(virtual_path, "/") do
                        table.insert(fragments, fragment)
                    end

                    local filters = {}
                    local cur_value
                    while #fragments > 0 do
                        local fragment = table.remove(fragments)
                        local meta = METADATA_SYMBOLS[fragment]
                        if meta and meta.db_column then
                            if cur_value ~= nil then
                                table.insert(filters, {meta.db_column, cur_value})
                            end
                        else
                            cur_value = fragment
                            if cur_value == "\u{2205}" then
                                cur_value = false
                            end
                        end
                    end

                    local FileManager = require("apps/filemanager/filemanager")
                    local file_chooser = FileManager.instance and FileManager.instance.file_chooser
                    if file_chooser then
                        local images = get_metadata_cover_widgets(max_img_w, max_img_h, base_dir, filters, file_chooser)
                        if #images > 0 then
                            if BookInfoManager:getSetting("use_stacked_foldercovers") then
                                return build_diagonal_stack(images, max_img_w, max_img_h)
                            else
                                return build_grid(images, max_img_w, max_img_h)
                            end
                        end
                    end
                end
            end
            return orig_getFolderCover(filepath, max_img_w, max_img_h)
        end
    end

    local orig_changeToPath = FileChooser.changeToPath
    function FileChooser:changeToPath(path, focused_path)
        if self.name == "filemanager" then
            if containsMetadataSegment(path) then
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
        end
        return orig_changeToPath(self, path, focused_path)
    end

    local ffiUtil_realpath = ffiUtil.realpath
    ffiUtil.realpath = function(path)
        if path ~= "/" and path:sub(-1) == "/" then
            path = path:sub(1, -2)
        end
        if FileChooser:getMetadataPathType(path) then
            if util.stringEndsWith(path, "/..") then
                return path:gsub("(/[^/]+/%.%.$", "")
            end
            return path
        end
        return ffiUtil_realpath(path)
    end

    local FileManager = require("apps/filemanager/filemanager")
    local FileManager_setupLayout = FileManager.setupLayout
    FileManager.setupLayout = function(self)
        FileManager_setupLayout(self)

        local file_chooser_showFileDialog = self.file_chooser.showFileDialog
        self.file_chooser.showFileDialog = function(self, item)
            if self:getMetadataPathType(item.path) then
                self.book_props = nil
                return true
            end
            return file_chooser_showFileDialog(self, item)
        end
    end

end

local METADATA_CONFIG = nil

userpatch.registerPatchPluginFunc("coverbrowser", function(CoverBrowser)
    local BookInfoManager = require("bookinfomanager")
    local util = require("util")
    local T = ffiUtil.template
    
    local CONFIG = METADATA_CONFIG or {
        ENABLE_DEBUG_LOGGING = false,
        MIN_BOOKS_FOR_GENRE = 1,
        MIN_BOOKS_FOR_YEAR = 1,
        CASE_SENSITIVE_GENRES = false,
        HIDE_EMPTY_VALUES = true,
        SHOW_BOOK_COUNT = true,
        GENRE_WHITELIST = {},
        GENRE_BLACKLIST = {},
    }

    local function isYear(value)
        if not value or type(value) ~= "string" then
            return false
        end
        value = value:match("^%s*(.-)%s*$")
        return value:match("^%d+$") ~= nil
    end
    
    local function shouldShowGenre(genre, whitelist, blacklist, case_sensitive)
        if not genre or genre == "" then
            return false
        end
        
        local genre_normalized = case_sensitive and genre or genre:lower()
        local function normalizeList(list)
            if not list or #list == 0 then return {} end
            local normalized = {}
            for _, item in ipairs(list) do
                table.insert(normalized, case_sensitive and item or item:lower())
            end
            return normalized
        end
        
        local whitelist_norm = normalizeList(whitelist)
        local blacklist_norm = normalizeList(blacklist)
        
        for _, blacklisted in ipairs(blacklist_norm) do
            if genre_normalized == blacklisted then
                return false
            end
        end
        
        if #whitelist_norm == 0 then
            return true
        end
        
        for _, whitelisted in ipairs(whitelist_norm) do
            if genre_normalized == whitelisted then
                return true
            end
        end
        
        return false
    end
    
    local function isEmptyValue(value)
        if not value then return true end
        if type(value) == "string" then
            local trimmed = value:match("^%s*(.-)%s*$")
            return trimmed == "" or trimmed == "\u{2205}"
        end
        return false
    end

    if not BookInfoManager.getMatchingMetadataValues then
        function BookInfoManager:getMatchingMetadataValues(base_dir, meta_name, filters)
            if meta_name == "genres" or meta_name == "year" then
                local vars = {}
                local sql = "select keywords, count(1) from bookinfo where directory glob ?"
                table.insert(vars, base_dir .. '/*')
                
                for _, filter in ipairs(filters) do
                    local name, value = filter[1], filter[2]
                    if value == false then
                        sql = T("%1 and keywords is NULL", sql)
                    elseif name == "genres" or name == "year" then
                        sql = T("%1 and '\n'||keywords||'\n' GLOB ?", sql)
                        table.insert(vars, "*\n" .. value .. "\n*")
                    elseif name == "authors" or name == "keywords" then
                        sql = T("%1 and '\n'||%2||'\n' GLOB ?", sql, name)
                        table.insert(vars, "*\n" .. value .. "\n*")
                    else
                        sql = T("%1 and %2=?", sql, name)
                        table.insert(vars, value)
                    end
                end
                
                sql = sql .. " group by keywords"
                self:openDbConnection()
                local stmt = self.db_conn:prepare(sql)
                stmt:bind(table.unpack(vars))
                local xresults = {}
                
                local logger = require("logger")
                while true do
                    local row = stmt:step()
                    if not row then
                        break
                    end
                    local keywords, nb = row[1] or false, tonumber(row[2])
                    if keywords then
                        for val in util.gsplit(keywords, "\n") do
                            if val and val ~= "" then
                                local is_year_val = isYear(val)
                                if CONFIG.ENABLE_DEBUG_LOGGING then
                                    if meta_name == "genres" then
                                        logger.dbg("Metadata genres: checking value:", val, "isYear:", is_year_val)
                                    elseif meta_name == "year" then
                                        logger.dbg("Metadata year: checking value:", val, "isYear:", is_year_val)
                                    end
                                end
                                if meta_name == "genres" and not is_year_val then
                                    if shouldShowGenre(val, CONFIG.GENRE_WHITELIST, CONFIG.GENRE_BLACKLIST, CONFIG.CASE_SENSITIVE_GENRES) then
                                        local key = CONFIG.CASE_SENSITIVE_GENRES and val or val:lower()
                                        xresults[key] = xresults[key] and (xresults[key] + nb) or nb
                                        if not CONFIG.CASE_SENSITIVE_GENRES and not xresults[key .. "_original"] then
                                            xresults[key .. "_original"] = val
                                        end
                                    end
                                elseif meta_name == "year" and is_year_val then
                                    xresults[val] = xresults[val] and (xresults[val] + nb) or nb
                                end
                            end
                        end
                    end
                end
                
                if CONFIG.ENABLE_DEBUG_LOGGING then
                    if meta_name == "genres" then
                        logger.dbg("Metadata genres: total unique values found:", util.tableSize(xresults))
                        for key, count in pairs(xresults) do
                            if not key:match("_original$") then
                                local display_val = CONFIG.CASE_SENSITIVE_GENRES and key or (xresults[key .. "_original"] or key)
                                logger.dbg("  -", display_val, ":", count)
                            end
                        end
                    elseif meta_name == "year" then
                        logger.dbg("Metadata year: total unique values found:", util.tableSize(xresults))
                        for val, count in pairs(xresults) do
                            logger.dbg("  -", val, ":", count)
                        end
                    end
                end
                
                local min_books = (meta_name == "genres") and CONFIG.MIN_BOOKS_FOR_GENRE or CONFIG.MIN_BOOKS_FOR_YEAR
                local results = {}
                for key, nb in pairs(xresults) do
                    if not key:match("_original$") then
                        local display_value = CONFIG.CASE_SENSITIVE_GENRES and key or (xresults[key .. "_original"] or key)
                        
                        if CONFIG.HIDE_EMPTY_VALUES and isEmptyValue(display_value) then
                        elseif nb >= min_books then
                            table.insert(results, {display_value, nb})
                        end
                    end
                end
                return results
            end
            
            local vars = {}
            local sql = T("select %1, count(1) from bookinfo where directory glob ?", meta_name)
            table.insert(vars, base_dir .. '/*')
            for _, filter in ipairs(filters) do
                local name, value = filter[1], filter[2]
                if value == false then
                    sql = T("%1 and %2 is NULL", sql, name)
                elseif name == "authors" or name == "keywords" then
                    sql = T("%1 and '\n'||%2||'\n' GLOB ?", sql, name)
                    table.insert(vars, "*\n" .. value .. "\n*")
                elseif name == "genres" or name == "year" then
                    if name == "genres" and not CONFIG.CASE_SENSITIVE_GENRES then
                        sql = T("%1 and lower('\n'||keywords||'\n') LIKE lower(?)", sql)
                        table.insert(vars, "%\n" .. value .. "\n%")
                    else
                        sql = T("%1 and '\n'||keywords||'\n' GLOB ?", sql)
                        table.insert(vars, "*\n" .. value .. "\n*")
                    end
                else
                    sql = T("%1 and %2=?", sql, name)
                    table.insert(vars, value)
                end
            end
            sql = T("%1 group by %2", sql, meta_name)
            self:openDbConnection()
            local stmt = self.db_conn:prepare(sql)
            stmt:bind(table.unpack(vars))
            local results = {}
            local xresults = {}
            local use_results_as_is = meta_name ~= "authors" and meta_name ~= "keywords"
            while true do
                local row = stmt:step()
                if not row then
                    break
                end
                if use_results_as_is then
                    local value = row[1] or false
                    local nb = tonumber(row[2])
                    if not CONFIG.HIDE_EMPTY_VALUES or not isEmptyValue(value) then
                        table.insert(results, {value, nb})
                    end
                else
                    local value, nb = row[1] or false, tonumber(row[2])
                    if value and value:find("\n") then
                        for val in util.gsplit(value, "\n") do
                            if not CONFIG.HIDE_EMPTY_VALUES or not isEmptyValue(val) then
                                xresults[val] = xresults[val] and (xresults[val] + nb) or nb
                            end
                        end
                    else
                        if not CONFIG.HIDE_EMPTY_VALUES or not isEmptyValue(value) then
                            xresults[value] = xresults[value] and (xresults[value] + nb) or nb
                        end
                    end
                end
            end
            if not use_results_as_is then
                for value, nb in pairs(xresults) do
                    table.insert(results, {value, nb})
                end
            end
            return results
        end
    end

    if not BookInfoManager.getMatchingFiles then
        function BookInfoManager:getMatchingFiles(base_dir, filters)
            local vars = {}
            local sql = "select directory||filename, filename from bookinfo where directory glob ?"
            table.insert(vars, base_dir .. '/*')
            for _, filter in ipairs(filters) do
                local name, value = filter[1], filter[2]
                if value == false then
                    sql = T("%1 and %2 is NULL", sql, name)
                elseif name == "authors" or name == "keywords" then
                    sql = T("%1 and '\n'||%2||'\n' GLOB ?", sql, name)
                    table.insert(vars, "*\n" .. value .. "\n*")
                elseif name == "genres" or name == "year" then
                    if name == "genres" and not CONFIG.CASE_SENSITIVE_GENRES then
                        sql = T("%1 and lower('\n'||keywords||'\n') LIKE lower(?)", sql)
                        table.insert(vars, "%\n" .. value .. "\n%")
                    else
                        sql = T("%1 and '\n'||keywords||'\n' GLOB ?", sql)
                        table.insert(vars, "*\n" .. value .. "\n*")
                    end
                else
                    sql = T("%1 and %2=?", sql, name)
                    table.insert(vars, value)
                end
            end
            self:openDbConnection()
            local stmt = self.db_conn:prepare(sql)
            stmt:bind(table.unpack(vars))
            local results = {}
            while true do
                local row = stmt:step()
                if not row then
                    break
                end
                table.insert(results, {row[1], row[2]})
            end
            return results
        end
    end

    if not CoverBrowser.getMatchingMetadataValues then
        function CoverBrowser:getMatchingMetadataValues(base_dir, meta_name, filters)
            return BookInfoManager:getMatchingMetadataValues(base_dir, meta_name, filters)
        end
    end

    if not CoverBrowser.getMatchingFiles then
        function CoverBrowser:getMatchingFiles(base_dir, filters)
            return BookInfoManager:getMatchingFiles(base_dir, filters)
        end
    end
end)

userpatch.registerPatchPluginFunc("coverbrowser", patchProjectTitleMetadataBrowser)

