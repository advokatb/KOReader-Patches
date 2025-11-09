--[[ Custom Folder Fonts for Project: Title
     
     This patch allows you to use custom fonts for folder names in Project: Title
     Works in both Cover Grid (mosaic) and List view modes
     
     Version: 3.0
]]--

local userpatch = require("userpatch")
local logger = require("logger")

local function patchProjectTitleFolderFonts(plugin)
    local Font = require("ui/font")
    local DataStorage = require("datastorage")
    local UIManager = require("ui/uimanager")
    local lfs = require("libs/libkoreader-lfs")
    local BookInfoManager = require("bookinfomanager")
    local ptutil = require("ptutil")
    
    -- Scan fonts directory and build font list
    local function getFontList()
        local fonts_dir = DataStorage:getDataDir() .. "/fonts"
        local font_list = {}
        
        local function scanDir(dir, relative_path)
            relative_path = relative_path or ""
            local ok, iter, dir_obj = pcall(lfs.dir, dir)
            if not ok then return end
            
            for entry in iter, dir_obj do
                if entry ~= "." and entry ~= ".." then
                    local full_path = dir .. "/" .. entry
                    local rel_path = relative_path ~= "" and (relative_path .. "/" .. entry) or entry
                    local mode = lfs.attributes(full_path, "mode")
                    
                    if mode == "directory" then
                        scanDir(full_path, rel_path)
                    elseif mode == "file" then
                        local ext = entry:match("%.([^%.]+)$")
                        if ext and (ext:lower() == "ttf" or ext:lower() == "otf") then
                            table.insert(font_list, {
                                name = entry:gsub("%.[^%.]+$", ""),
                                path = rel_path,
                                full_path = full_path,
                            })
                        end
                    end
                end
            end
        end
        
        scanDir(fonts_dir)
        table.sort(font_list, function(a, b) return a.path:lower() < b.path:lower() end)
        return font_list
    end
    
    -- Apply custom font to folder names
    local custom_font = BookInfoManager:getSetting("custom_folder_font")
    
    if custom_font and custom_font ~= "" then
        custom_font = custom_font:gsub("\\", "/")
        local font_path = DataStorage:getDataDir() .. "/fonts/" .. custom_font
        local font_exists = lfs.attributes(font_path, "mode") == "file"
        
        if font_exists then
            ptutil.good_serif = font_path
            ptutil.good_sans = font_path
            logger.info("Custom folder fonts applied:", custom_font)
        end
    end
    
    -- Apply custom font size adjustment
    local size_adjustment = BookInfoManager:getSetting("custom_folder_font_size") or 0
    if size_adjustment ~= 0 then
        ptutil.grid_defaults.dir_font_nominal = ptutil.grid_defaults.dir_font_nominal + size_adjustment
        ptutil.grid_defaults.dir_font_min = math.max(12, ptutil.grid_defaults.dir_font_min + size_adjustment)
        logger.info("Folder font size adjusted by:", size_adjustment)
    end
    
    -- Add menu for font settings
    local CoverBrowser = plugin
    local orig_addToMainMenu = CoverBrowser.addToMainMenu
    
    function CoverBrowser:addToMainMenu(menu_items)
        orig_addToMainMenu(self, menu_items)
        
        local _ = require("gettext")
        local T = require("ffi/util").template
        
        if menu_items.filemanager_display_mode and menu_items.filemanager_display_mode.sub_item_table then
            for i, item in ipairs(menu_items.filemanager_display_mode.sub_item_table) do
                if item.text == _("Advanced settings") and item.sub_item_table then
                    -- Add new Fonts section
                    table.insert(item.sub_item_table, {
                        text = "Folder Fonts",
                        sub_item_table = {
                            -- Font selector
                            {
                                text_func = function()
                                    local current = BookInfoManager:getSetting("custom_folder_font")
                                    if current and current ~= "" then
                                        local display_name = current:match("([^/\\]+)$") or current
                                        return "Custom font: " .. display_name
                                    else
                                        return "Custom font: Default"
                                    end
                                end,
                                sub_item_table_func = function()
                                    local font_list = getFontList()
                                    local items = {}
                                    local current_font = BookInfoManager:getSetting("custom_folder_font") or ""
                                    
                                    -- Default font option
                                    table.insert(items, {
                                        text = "Use default font",
                                        help_text = "SourceSerif4 / SourceSans3",
                                        checked_func = function() return current_font == "" end,
                                        callback = function()
                                            BookInfoManager:saveSetting("custom_folder_font", "")
                                            local InfoMessage = require("ui/widget/infomessage")
                                            UIManager:show(InfoMessage:new{
                                                text = "Switched to default font\n\nRestarting...",
                                                timeout = 2,
                                            })
                                            UIManager:scheduleIn(2, function() UIManager:askForRestart() end)
                                        end,
                                    })
                                    
                                    if #font_list > 0 then
                                        table.insert(items, { text = "────────────────────────", separator = true })
                                    end
                                    
                                    -- Custom fonts
                                    for _, font_info in ipairs(font_list) do
                                        table.insert(items, {
                                            text = font_info.name,
                                            help_text = font_info.path,
                                            checked_func = function()
                                                return current_font:gsub("\\", "/") == font_info.path
                                            end,
                                            font_func = function(size)
                                                local ok, face = pcall(Font.getFace, Font, font_info.full_path, size)
                                                return ok and face or Font:getFace("cfont", size)
                                            end,
                                            callback = function()
                                                BookInfoManager:saveSetting("custom_folder_font", font_info.path)
                                                local InfoMessage = require("ui/widget/infomessage")
                                                UIManager:show(InfoMessage:new{
                                                    text = T("Font: %1\n\nPath: %2\n\nRestarting...", 
                                                             font_info.name, font_info.path),
                                                    timeout = 2,
                                                })
                                                UIManager:scheduleIn(2, function() UIManager:askForRestart() end)
                                            end,
                                        })
                                    end
                                    
                                    if #font_list == 0 then
                                        table.insert(items, { text = "No fonts found", enabled = false })
                                    end
                                    
                                    return items
                                end,
                            },
                            -- Font size adjustment
                            {
                                text_func = function()
                                    local adjustment = BookInfoManager:getSetting("custom_folder_font_size") or 0
                                    if adjustment == 0 then
                                        return "Font size: Default"
                                    elseif adjustment > 0 then
                                        return T("Font size: +%1", adjustment)
                                    else
                                        return T("Font size: %1", adjustment)
                                    end
                                end,
                                sub_item_table = {
                                    {
                                        text = "Default (0)",
                                        checked_func = function() 
                                            return (BookInfoManager:getSetting("custom_folder_font_size") or 0) == 0 
                                        end,
                                        callback = function()
                                            BookInfoManager:saveSetting("custom_folder_font_size", 0)
                                            UIManager:askForRestart()
                                        end,
                                    },
                                    {
                                        text = "Tiny (-4)",
                                        checked_func = function() 
                                            return BookInfoManager:getSetting("custom_folder_font_size") == -4 
                                        end,
                                        callback = function()
                                            BookInfoManager:saveSetting("custom_folder_font_size", -4)
                                            UIManager:askForRestart()
                                        end,
                                    },
                                    {
                                        text = "Small (-2)",
                                        checked_func = function() 
                                            return BookInfoManager:getSetting("custom_folder_font_size") == -2 
                                        end,
                                        callback = function()
                                            BookInfoManager:saveSetting("custom_folder_font_size", -2)
                                            UIManager:askForRestart()
                                        end,
                                    },
                                    {
                                        text = "Large (+2)",
                                        checked_func = function() 
                                            return BookInfoManager:getSetting("custom_folder_font_size") == 2 
                                        end,
                                        callback = function()
                                            BookInfoManager:saveSetting("custom_folder_font_size", 2)
                                            UIManager:askForRestart()
                                        end,
                                    },
                                    {
                                        text = "Extra Large (+4)",
                                        checked_func = function() 
                                            return BookInfoManager:getSetting("custom_folder_font_size") == 4 
                                        end,
                                        callback = function()
                                            BookInfoManager:saveSetting("custom_folder_font_size", 4)
                                            UIManager:askForRestart()
                                        end,
                                    },
                                    {
                                        text = "Huge (+6)",
                                        checked_func = function() 
                                            return BookInfoManager:getSetting("custom_folder_font_size") == 6 
                                        end,
                                        callback = function()
                                            BookInfoManager:saveSetting("custom_folder_font_size", 6)
                                            UIManager:askForRestart()
                                        end,
                                    },
                                },
                            },
                        },
                    })
                    break
                end
            end
        end
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchProjectTitleFolderFonts)

logger.info("Custom folder fonts patch loaded - v3.0")

