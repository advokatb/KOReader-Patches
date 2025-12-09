--[[
    Project: Title Book Spine Effect (Apple Books style)
    
    Adds a pressed book spine effect to book covers in Project: Title view,
    similar to Apple Books. Creates a subtle shadow/gradient along the left edge
    of book covers to simulate a pressed spine.
]]--

local userpatch = require("userpatch")
local logger = require("logger")
local Blitbuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local _ = require("gettext")
local DataStorage = require("datastorage")
local IconWidget = require("ui/widget/iconwidget")
local util = require("util")

local function patchProjectTitleSpineEffect(plugin)
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    
    if not MosaicMenuItem then
        return
    end
    
    if MosaicMenuItem._spine_effect_patch_applied then
        return
    end
    MosaicMenuItem._spine_effect_patch_applied = true
    
    local BookInfoManager = userpatch.getUpValue(MosaicMenuItem.update, "BookInfoManager")
    if not BookInfoManager then
        return
    end
    
    -- Settings
    local function BooleanSetting(text, name, default)
        local self = { text = text }
        self.get = function()
            local setting = BookInfoManager:getSetting(name)
            if setting == nil then return default end
            return setting
        end
        self.toggle = function()
            local current = self.get()
            BookInfoManager:saveSetting(name, not current)
            return not current
        end
        return self
    end
    
    local function NumberSetting(text, name, default, min_val, max_val)
        local self = { text = text }
        self.get = function()
            local setting = BookInfoManager:getSetting(name)
            if setting == nil then return default end
            return math.max(min_val, math.min(max_val, setting))
        end
        self.set = function(value)
            BookInfoManager:saveSetting(name, math.max(min_val, math.min(max_val, value)))
        end
        return self
    end
    
    local settings = {
        enabled = BooleanSetting(_("Book spine shadow effect"), "pt_spine_effect_enabled", true),
        shadow_width = NumberSetting(_("Spine shadow width"), "pt_spine_shadow_width", Screen:scaleBySize(8), Screen:scaleBySize(2), Screen:scaleBySize(20)),
        shadow_intensity = NumberSetting(_("Spine shadow intensity"), "pt_spine_shadow_intensity", 0.25, 0.1, 0.5),
        left_offset = NumberSetting(_("Spine offset from edge"), "pt_spine_left_offset", Screen:scaleBySize(15), Screen:scaleBySize(5), Screen:scaleBySize(30)),
    }
    
    local spine_icon_path = DataStorage:getDataDir() .. "/icons/book.spine.svg"
    local spine_icon_exists = util.fileExists(spine_icon_path)
    local orig_paintTo = MosaicMenuItem.paintTo
    
    function MosaicMenuItem:paintTo(bb, x, y)
        orig_paintTo(self, bb, x, y)
        
        if self.is_directory or not self._has_cover_image then
            return
        end
        
        local target = self[1] and self[1][1] and self[1][1][1]
        if not target or not target.dimen then
            return
        end
        
        local fx = x + math.floor((self.width - target.dimen.w) / 2)
        local fy = y + math.floor((self.height - target.dimen.h) / 2)
        local fh = target.dimen.h
        
        local shadow_width = settings.shadow_width.get()
        local shadow_intensity = settings.shadow_intensity.get()
        local left_offset = settings.left_offset.get()
        
        if spine_icon_exists then
            local scaled_spine = IconWidget:new{
                icon = "book.spine",
                alpha = true,
                height = fh,
            }
            scaled_spine:paintTo(bb, fx + left_offset, fy)
        else
            local steps = math.max(4, math.floor(shadow_width / 1.5))
            local step_width = shadow_width / steps
            
            for i = 0, steps - 1 do
                local strip_x = fx + left_offset + (i * step_width)
                local strip_w = math.ceil(step_width)
                if i == steps - 1 then
                    strip_w = math.ceil(fx + left_offset + shadow_width - strip_x)
                end
                
                local progress = i / (steps - 1)
                local intensity = shadow_intensity * (1.0 - (progress * progress))
                
                if intensity > 0.01 then
                    bb:darkenRect(math.floor(strip_x), fy, strip_w, fh, intensity)
                end
            end
        end
    end
    
    local CoverBrowser = plugin
    local orig_addToMainMenu = CoverBrowser.addToMainMenu
    
    function CoverBrowser:addToMainMenu(menu_items)
        orig_addToMainMenu(self, menu_items)
        
        if menu_items.filemanager_display_mode and menu_items.filemanager_display_mode.sub_item_table then
            for i, item in ipairs(menu_items.filemanager_display_mode.sub_item_table) do
                if item.text == _("Advanced settings") and item.sub_item_table then
                    for _, sub_item in ipairs(item.sub_item_table) do
                        if sub_item.text == "Book Spine Effect" then
                            return
                        end
                    end
                    table.insert(item.sub_item_table, {
                        text = "Book Spine Effect",
                        sub_item_table = {
                            -- Shadow width setting
                            {
                                text_func = function()
                                    local current = settings.shadow_width.get()
                                    local small = Screen:scaleBySize(4)
                                    local medium = Screen:scaleBySize(8)
                                    local large = Screen:scaleBySize(12)
                                    
                                    if current < small + 1 then
                                        return "Shadow width: Small"
                                    elseif current < medium + 1 then
                                        return "Shadow width: Medium"
                                    elseif current < large + 1 then
                                        return "Shadow width: Large"
                                    else
                                        return "Shadow width: Extra Large"
                                    end
                                end,
                                sub_item_table = {
                                    {
                                        text = "Small",
                                        checked_func = function() 
                                            return settings.shadow_width.get() < Screen:scaleBySize(6)
                                        end,
                                        callback = function()
                                            settings.shadow_width.set(Screen:scaleBySize(4))
                                            if self.ui and self.ui.file_chooser then
                                                self.ui.file_chooser:updateItems()
                                            end
                                        end,
                                    },
                                    {
                                        text = "Medium",
                                        checked_func = function() 
                                            local current = settings.shadow_width.get()
                                            return current >= Screen:scaleBySize(6) and current < Screen:scaleBySize(10)
                                        end,
                                        callback = function()
                                            settings.shadow_width.set(Screen:scaleBySize(8))
                                            if self.ui and self.ui.file_chooser then
                                                self.ui.file_chooser:updateItems()
                                            end
                                        end,
                                    },
                                    {
                                        text = "Large",
                                        checked_func = function() 
                                            local current = settings.shadow_width.get()
                                            return current >= Screen:scaleBySize(10) and current < Screen:scaleBySize(16)
                                        end,
                                        callback = function()
                                            settings.shadow_width.set(Screen:scaleBySize(12))
                                            if self.ui and self.ui.file_chooser then
                                                self.ui.file_chooser:updateItems()
                                            end
                                        end,
                                    },
                                    {
                                        text = "Extra Large",
                                        checked_func = function() 
                                            return settings.shadow_width.get() >= Screen:scaleBySize(16)
                                        end,
                                        callback = function()
                                            settings.shadow_width.set(Screen:scaleBySize(20))
                                            if self.ui and self.ui.file_chooser then
                                                self.ui.file_chooser:updateItems()
                                            end
                                        end,
                                    },
                                },
                            },
                            -- Shadow intensity setting
                            {
                                text_func = function()
                                    local current = settings.shadow_intensity.get()
                                    local light = 0.15
                                    local medium = 0.25
                                    local dark = 0.35
                                    
                                    if current < light + 0.05 then
                                        return "Shadow intensity: Light"
                                    elseif current < medium + 0.05 then
                                        return "Shadow intensity: Medium"
                                    elseif current < dark + 0.05 then
                                        return "Shadow intensity: Dark"
                                    else
                                        return "Shadow intensity: Very Dark"
                                    end
                                end,
                                sub_item_table = {
                                    {
                                        text = "Light",
                                        checked_func = function() 
                                            return settings.shadow_intensity.get() < 0.2
                                        end,
                                        callback = function()
                                            settings.shadow_intensity.set(0.15)
                                            if self.ui and self.ui.file_chooser then
                                                self.ui.file_chooser:updateItems()
                                            end
                                        end,
                                    },
                                    {
                                        text = "Medium",
                                        checked_func = function() 
                                            local current = settings.shadow_intensity.get()
                                            return current >= 0.2 and current < 0.3
                                        end,
                                        callback = function()
                                            settings.shadow_intensity.set(0.25)
                                            if self.ui and self.ui.file_chooser then
                                                self.ui.file_chooser:updateItems()
                                            end
                                        end,
                                    },
                                    {
                                        text = "Dark",
                                        checked_func = function() 
                                            local current = settings.shadow_intensity.get()
                                            return current >= 0.3 and current < 0.4
                                        end,
                                        callback = function()
                                            settings.shadow_intensity.set(0.35)
                                            if self.ui and self.ui.file_chooser then
                                                self.ui.file_chooser:updateItems()
                                            end
                                        end,
                                    },
                                    {
                                        text = "Very Dark",
                                        checked_func = function() 
                                            return settings.shadow_intensity.get() >= 0.4
                                        end,
                                        callback = function()
                                            settings.shadow_intensity.set(0.45)
                                            if self.ui and self.ui.file_chooser then
                                                self.ui.file_chooser:updateItems()
                                            end
                                        end,
                                    },
                                },
                            },
                            -- Left offset setting
                            {
                                text_func = function()
                                    local current = settings.left_offset.get()
                                    local small = Screen:scaleBySize(12)
                                    local medium = Screen:scaleBySize(15)
                                    local large = Screen:scaleBySize(22)
                                    
                                    if current < small + 1 then
                                        return "Offset from edge: Small"
                                    elseif current < medium + 1 then
                                        return "Offset from edge: Medium"
                                    elseif current < large + 1 then
                                        return "Offset from edge: Large"
                                    else
                                        return "Offset from edge: Extra Large"
                                    end
                                end,
                                sub_item_table = {
                                    {
                                        text = "Small",
                                        checked_func = function() 
                                            return settings.left_offset.get() < Screen:scaleBySize(12)
                                        end,
                                        callback = function()
                                            settings.left_offset.set(Screen:scaleBySize(12))
                                            if self.ui and self.ui.file_chooser then
                                                self.ui.file_chooser:updateItems()
                                            end
                                        end,
                                    },
                                    {
                                        text = "Medium",
                                        checked_func = function() 
                                            local current = settings.left_offset.get()
                                            return current >= Screen:scaleBySize(12) and current < Screen:scaleBySize(19)
                                        end,
                                        callback = function()
                                            settings.left_offset.set(Screen:scaleBySize(15))
                                            if self.ui and self.ui.file_chooser then
                                                self.ui.file_chooser:updateItems()
                                            end
                                        end,
                                    },
                                    {
                                        text = "Large",
                                        checked_func = function() 
                                            local current = settings.left_offset.get()
                                            return current >= Screen:scaleBySize(19) and current < Screen:scaleBySize(26)
                                        end,
                                        callback = function()
                                            settings.left_offset.set(Screen:scaleBySize(22))
                                            if self.ui and self.ui.file_chooser then
                                                self.ui.file_chooser:updateItems()
                                            end
                                        end,
                                    },
                                    {
                                        text = "Extra Large",
                                        checked_func = function() 
                                            return settings.left_offset.get() >= Screen:scaleBySize(26)
                                        end,
                                        callback = function()
                                            settings.left_offset.set(Screen:scaleBySize(30))
                                            if self.ui and self.ui.file_chooser then
                                                self.ui.file_chooser:updateItems()
                                            end
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
    
    logger.info("PT Book Spine Effect: Patch loaded and applied")
end

userpatch.registerPatchPluginFunc("coverbrowser", patchProjectTitleSpineEffect)

local UIManager = require("ui/uimanager")
UIManager:nextTick(function()
    local PluginLoader = require("pluginloader")
    local plugin_instance = PluginLoader:getPluginInstance("coverbrowser")
    if plugin_instance then
        patchProjectTitleSpineEffect(plugin_instance)
    end
end)

