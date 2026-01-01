--[[
    Patch: Filter Folders by Book Status for Project Title
    Author: advokatb
    
    When filtering by "Book Status" (New, Reading, etc.) in ProjectTitle, 
    this patch hides folders that do not contain any books matching the current filter.
    It performs a recursive scan of subdirectories.
    
    This patch automatically loads the last saved filter state on startup.
]]

local lfs = require("libs/libkoreader-lfs")
local BookList = require("ui/widget/booklist")
local DocumentRegistry = require("document/documentregistry")
local FileChooser = require("ui/widget/filechooser")
local UIManager = require("ui/uimanager")
local logger = require("logger")
local dbg = require("dbg")

local function scanDirForStatus(path, allowed_statuses)
    local iter, dir_obj = lfs.dir(path)
    if not iter then
        dbg:guard(dbg.is_on, function() logger.dbg("[Patch] Cannot open dir:", path) end)
        return false
    end

    for file in iter, dir_obj do
        if file ~= "." and file ~= ".." then
            local fpath = path .. "/" .. file
            local attr = lfs.attributes(fpath)
            if attr then
                if attr.mode == "directory" then
                    if scanDirForStatus(fpath, allowed_statuses) then
                        return true
                    end
                elseif attr.mode == "file" then
                    if DocumentRegistry:hasProvider(fpath) then
                        local status = BookList.getBookStatus(fpath)
                        if allowed_statuses[status] then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

local function applyPatch()
    local ok, CoverMenu = pcall(require, "covermenu")
    if not ok or not CoverMenu then
        return false
    end

    if CoverMenu._filter_folders_patch_applied then
        return true
    end
    CoverMenu._filter_folders_patch_applied = true

    local saved_filter = G_reader_settings:readSetting("show_filter", {})
    if saved_filter and saved_filter.status then
        FileChooser.show_filter.status = saved_filter.status
    end

    local orig_FileChooser_genItemTable = CoverMenu._FileChooser_genItemTable_orig

    CoverMenu._FileChooser_genItemTable_orig = function(self, dirs, files, path)
        local item_table = orig_FileChooser_genItemTable(self, dirs, files, path)

        if not FileChooser.show_filter or not FileChooser.show_filter.status then
            return item_table
        end

        local allowed = FileChooser.show_filter.status
        local filtered_table = {}
        local has_regular_items = false

        for _, item in ipairs(item_table) do
            local keep = false
            local is_navigation = false
            
            if item.is_go_up then
                is_navigation = true
                keep = true
            elseif item.path and (item.path:match("/%.%.$") or item.path:match("/%.$")) then
                is_navigation = true
                keep = true
            elseif item.text and (item.text:match("^⬆") or item.text:match("^%.%.")) then
                is_navigation = true
                keep = true
            elseif not item.is_file and not item.path then
                is_navigation = true
                keep = true
            else
                local attr = item.path and lfs.attributes(item.path)
                if attr and attr.mode == "directory" then
                    if scanDirForStatus(item.path, allowed) then
                        keep = true
                        has_regular_items = true
                    end
                elseif item.is_file or (attr and attr.mode == "file") then
                    if DocumentRegistry:hasProvider(item.path) then
                       local status = BookList.getBookStatus(item.path)
                       if allowed[status] then
                           keep = true
                           has_regular_items = true
                       end
                    else
                       keep = true
                       has_regular_items = true
                    end
                else
                    keep = true
                end
            end

            if keep then
                table.insert(filtered_table, item)
            end
        end

        -- If no regular items remain after filtering, return original
        -- This prevents crash when last book in folder is marked complete
        if not has_regular_items and #item_table > 1 then
            return item_table
        end

        return filtered_table
    end

    logger.info("[Patch] \"Filter Folders by Status\" applied")
    return true
end

if not applyPatch() then
    UIManager:nextTick(function()
        if applyPatch() then
            UIManager:nextTick(function()
                local FileManager = require("apps/filemanager/filemanager")
                if FileManager.instance and FileManager.instance.file_chooser then
                    FileManager.instance.file_chooser:refreshPath()
                end
            end)
        end
    end)
end
