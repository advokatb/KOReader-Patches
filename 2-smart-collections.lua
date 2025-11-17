-- Smart Collections userpatch
-- 
-- Adds automatic collections based on metadata rules (author, date, tags, series, language, etc.)
-- Supports combined conditions (AND/OR)
-- Collections are automatically updated when books are added/modified
--
-- Usage:
-- 1. Create a collection and connect at least one folder to it
-- 2. Long-press on the collection in the collections list
-- 3. Select "Make smart collection"
-- 4. Add rules (e.g., "Authors contains Tolkien", "Series equals Harry Potter")
-- 5. Choose how to combine rules (AND = all must match, OR = any must match)
-- 6. Save rules - the collection will be automatically updated
--
-- Smart collections are marked with a 💡 icon
-- Rules are automatically re-evaluated when book metadata changes
--
-- Author: advokatb
-- License: AGPL v3

local userpatch = require("userpatch")
local ReadCollection = require("readcollection")
local FileManagerCollection = require("apps/filemanager/filemanagercollection")
local UIManager = require("ui/uimanager")
local InputDialog = require("ui/widget/inputdialog")
local ButtonDialog = require("ui/widget/buttondialog")
local CheckButton = require("ui/widget/checkbutton")
local InfoMessage = require("ui/widget/infomessage")
local ConfirmBox = require("ui/widget/confirmbox")
local Menu = require("ui/widget/menu")
local SpinWidget = require("ui/widget/spinwidget")
local ffiUtil = require("ffi/util")
local util = require("util")
local _ = require("gettext")
local T = ffiUtil.template
local logger = require("logger")
local lfs = require("libs/libkoreader-lfs")
local DocumentRegistry = require("document/documentregistry")

-- Settings storage
local LuaSettings = require("luasettings")
local DataStorage = require("datastorage")
local smart_collections_file = DataStorage:getSettingsDir() .. "/smart_collections.lua"
local smart_collections_settings = LuaSettings:open(smart_collections_file)

-- Smart collection marker
local SMART_COLLECTION_MARKER = "\u{1F4A1}" -- 💡 light bulb emoji

-- Rule operators
local OPERATORS = {
    EQUALS = "equals",
    CONTAINS = "contains",
    STARTS_WITH = "starts_with",
    ENDS_WITH = "ends_with",
    NOT_EQUALS = "not_equals",
    NOT_CONTAINS = "not_contains",
    GREATER_THAN = "greater_than",
    LESS_THAN = "less_than",
    IS_EMPTY = "is_empty",
    IS_NOT_EMPTY = "is_not_empty",
}

-- Metadata fields
local METADATA_FIELDS = {
    authors = { text = _("Authors"), multi_value = true },
    title = { text = _("Title"), multi_value = false },
    series = { text = _("Series"), multi_value = false },
    keywords = { text = _("Keywords"), multi_value = true },
    language = { text = _("Language"), multi_value = false },
    pubdate = { text = _("Publication date"), multi_value = false },
    pages = { text = _("Pages"), multi_value = false, numeric = true },
}

-- Condition operators for UI
local OPERATOR_TEXTS = {
    [OPERATORS.EQUALS] = _("equals"),
    [OPERATORS.CONTAINS] = _("contains"),
    [OPERATORS.STARTS_WITH] = _("starts with"),
    [OPERATORS.ENDS_WITH] = _("ends with"),
    [OPERATORS.NOT_EQUALS] = _("not equals"),
    [OPERATORS.NOT_CONTAINS] = _("not contains"),
    [OPERATORS.GREATER_THAN] = _("greater than"),
    [OPERATORS.LESS_THAN] = _("less than"),
    [OPERATORS.IS_EMPTY] = _("is empty"),
    [OPERATORS.IS_NOT_EMPTY] = _("is not empty"),
}

-- Load smart collection rules
local function loadSmartCollectionRules()
    return smart_collections_settings:readSetting("rules", {})
end

-- Save smart collection rules
local function saveSmartCollectionRules(rules)
    smart_collections_settings:saveSetting("rules", rules)
    smart_collections_settings:flush()
end

-- Check if a collection is a smart collection
local function isSmartCollection(collection_name)
    local rules = loadSmartCollectionRules()
    return rules[collection_name] ~= nil
end

-- Evaluate a single value against operator (defined before evaluateCondition)
local function evaluateSingleValue(field_value, operator, value)
    if not field_value then return false end
    
    field_value = tostring(field_value)
    value = value and tostring(value) or ""
    
    -- For case-insensitive comparison, convert to lowercase
    local field_lower = field_value:lower()
    local value_lower = value:lower()
    
    if operator == OPERATORS.EQUALS then
        return field_lower == value_lower
    elseif operator == OPERATORS.CONTAINS then
        -- Use pattern matching with escaped special characters
        local pattern = value_lower:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1")
        return field_lower:find(pattern) ~= nil
    elseif operator == OPERATORS.STARTS_WITH then
        local pattern = "^" .. value_lower:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1")
        return field_lower:find(pattern) ~= nil
    elseif operator == OPERATORS.ENDS_WITH then
        local pattern = value_lower:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1") .. "$"
        return field_lower:find(pattern) ~= nil
    elseif operator == OPERATORS.NOT_EQUALS then
        return field_lower ~= value_lower
    elseif operator == OPERATORS.NOT_CONTAINS then
        local pattern = value_lower:gsub("[%(%)%.%+%-%*%?%[%]%^%$%%]", "%%%1")
        return field_lower:find(pattern) == nil
    elseif operator == OPERATORS.GREATER_THAN then
        return tonumber(field_value) and tonumber(value) and tonumber(field_value) > tonumber(value)
    elseif operator == OPERATORS.LESS_THAN then
        return tonumber(field_value) and tonumber(value) and tonumber(field_value) < tonumber(value)
    end
    
    return false
end

-- Evaluate a single rule condition
local function evaluateCondition(book_props, field, operator, value)
    local field_value = book_props[field]
    
    -- Handle multi-value fields (authors, keywords)
    local field_metadata = METADATA_FIELDS[field]
    if field_metadata and field_metadata.multi_value and field_value then
        -- Split by newline and check each value
        local values = util.splitToArray(field_value, "\n")
        for _, v in ipairs(values) do
            if evaluateSingleValue(v, operator, value) then
                return true
            end
        end
        return false
    end
    
    -- Handle empty values
    if not field_value or field_value == "" then
        if operator == OPERATORS.IS_EMPTY then
            return true
        elseif operator == OPERATORS.IS_NOT_EMPTY then
            return false
        else
            return false
        end
    end
    
    if operator == OPERATORS.IS_EMPTY then
        return false
    elseif operator == OPERATORS.IS_NOT_EMPTY then
        return true
    end
    
    return evaluateSingleValue(field_value, operator, value)
end

-- Evaluate all rules for a collection
local function evaluateRules(book_props, rules)
    if not rules or #rules == 0 then
        return false
    end
    
    local combine_operator = rules.combine_operator or "AND"
    
    if combine_operator == "AND" then
        -- All conditions must be true
        for _, rule in ipairs(rules) do
            if not evaluateCondition(book_props, rule.field, rule.operator, rule.value) then
                return false
            end
        end
        return true
    else
        -- OR: At least one condition must be true
        for _, rule in ipairs(rules) do
            if evaluateCondition(book_props, rule.field, rule.operator, rule.value) then
                return true
            end
        end
        return false
    end
end

-- Store BookInfoManager reference
local SMART_COLLECTIONS_DEBUG = false -- Set to true to log detailed diagnostics

local function logDebug(...)
    if SMART_COLLECTIONS_DEBUG then
        logger.info(...)
    end
end

local BookInfoManagerRef = nil

-- Update a smart collection based on its rules
local function updateSmartCollection(collection_name, rules)
    if not rules or #rules == 0 then
        return 0
    end
    
    -- Use stored BookInfoManager reference
    local BookInfoManager = BookInfoManagerRef
    if not BookInfoManager then
        logger.warn("Smart Collections: BookInfoManager not available - CoverBrowser plugin may not be loaded")
        return 0
    end
    
    local added_count = 0
    local removed_count = 0
    
    -- Get all books from connected folders or scan all books
    local coll_settings = ReadCollection.coll_settings[collection_name]
    if not coll_settings then
        logger.warn("Smart Collections: Collection settings not found for", collection_name)
        return 0
    end
    
    local folders = coll_settings.folders
    local files_to_check = {}
    
    if folders then
        logDebug("Smart Collections: Found", util.tableSize(folders), "connected folder(s)")
        -- Scan connected folders
        for folder, folder_settings in pairs(folders) do
            -- Normalize folder path
            folder = ffiUtil.realpath(folder) or folder
            local subfolders_setting = folder_settings.subfolders
            
            -- Check if folder exists
            local folder_attr = lfs.attributes(folder)
            if not folder_attr then
                logger.warn("Smart Collections: Folder does not exist:", folder)
            else
                -- First, try scanning without subfolders
                local files_in_folder = 0
                local all_files_in_folder = 0
                local files_found_directly = {}
                
                util.findFiles(folder, function(file, f, attr)
                    all_files_in_folder = all_files_in_folder + 1
                    if attr and attr.mode == "file" then
                        file = ffiUtil.realpath(file) or file
                        if DocumentRegistry:hasProvider(file) then
                            files_found_directly[file] = true
                            files_in_folder = files_in_folder + 1
                        end
                    end
                end, false) -- Don't scan subfolders first
                
                logDebug("Smart Collections: Found", files_in_folder, "books directly in folder", folder)
                
                -- Add files found directly
                for file in pairs(files_found_directly) do
                    files_to_check[file] = true
                end
                
                -- Determine if we should scan subfolders
                local should_scan_subfolders = false
                if subfolders_setting == true then
                    -- Explicitly enabled
                    should_scan_subfolders = true
                    logDebug("Smart Collections: Subfolders explicitly enabled in settings")
                elseif subfolders_setting == nil or subfolders_setting == false then
                    -- Not set or explicitly disabled - but for smart collections, scan if no books in root
                    if files_in_folder == 0 then
                        should_scan_subfolders = true
                        logDebug("Smart Collections: No books in root folder, automatically scanning subfolders...")
                    end
                end
                
                if should_scan_subfolders then
                    local files_in_subfolders = 0
                    local all_files_in_subfolders = 0
                    
                    util.findFiles(folder, function(file, f, attr)
                        all_files_in_subfolders = all_files_in_subfolders + 1
                        if attr and attr.mode == "file" then
                            file = ffiUtil.realpath(file) or file
                            if DocumentRegistry:hasProvider(file) then
                                files_to_check[file] = true
                                files_in_subfolders = files_in_subfolders + 1
                            end
                        end
                    end, true) -- Scan subfolders
                    
                    logDebug("Smart Collections: Found", files_in_subfolders, "books in subfolders out of", all_files_in_subfolders, "total files")
                end
            end
        end
    else
        -- If no folders connected, we can't auto-update
        logger.warn("Smart Collections: No folders connected to collection", collection_name)
        return 0
    end
    
    logDebug("Smart Collections: Total files to check:", util.tableSize(files_to_check))
    
    -- Check each file
    local files_checked = 0
    local files_with_metadata = 0
    local matches_count = 0
    for file in pairs(files_to_check) do
        files_checked = files_checked + 1
        local book_props = BookInfoManager:getDocProps(file)
        if book_props and next(book_props) then
            files_with_metadata = files_with_metadata + 1
            local matches = evaluateRules(book_props, rules)
            local is_in_collection = ReadCollection:isFileInCollection(file, collection_name)
            
            if matches then
                matches_count = matches_count + 1
            end
            
            -- Debug logging for first few files
            if SMART_COLLECTIONS_DEBUG and files_checked <= 5 then
                logger.info("Smart Collections: File", file:match("([^/]+)$"))
                logger.info("Smart Collections: Authors", book_props.authors)
                logger.info("Smart Collections: Matches rules", matches, "Is in collection:", is_in_collection)
                -- Log rule details
                if rules and #rules > 0 then
                    for i, rule in ipairs(rules) do
                        local field_value = book_props[rule.field] or "(empty)"
                        logger.info("Smart Collections: Rule", i, "Field:", rule.field, "Operator:", rule.operator, "Value:", rule.value, "Field value:", field_value)
                    end
                end
            end
            
            if matches and not is_in_collection then
                ReadCollection:addItem(file, collection_name)
                added_count = added_count + 1
                logDebug("Smart Collections: Added", file, "authors:", book_props.authors)
            elseif not matches and is_in_collection then
                ReadCollection:removeItem(file, collection_name, true)
                removed_count = removed_count + 1
                logDebug("Smart Collections: Removed", file)
            end
        else
            if SMART_COLLECTIONS_DEBUG and files_checked <= 3 then
                logger.info("Smart Collections: No metadata for", file)
            end
        end
    end
    
    logDebug("Smart Collections: Matches found:", matches_count, "out of", files_with_metadata, "books with metadata")
    
    logDebug("Smart Collections: Checked", files_checked, "files,", files_with_metadata, "with metadata")
    
    if added_count > 0 or removed_count > 0 then
        ReadCollection:write({ [collection_name] = true })
        logDebug("Smart Collections: Updated", collection_name, "added:", added_count, "removed:", removed_count)
    end
    
    return added_count + removed_count
end

-- Update all smart collections
local function updateAllSmartCollections()
    local rules = loadSmartCollectionRules()
    local updated = false
    
    for collection_name, collection_rules in pairs(rules) do
        if ReadCollection.coll[collection_name] then
            local count = updateSmartCollection(collection_name, collection_rules)
            if count > 0 then
                updated = true
            end
        end
    end
    
    return updated
end

-- Get operator options for a field
local function getOperatorOptions(field)
    local field_metadata = METADATA_FIELDS[field]
    if not field_metadata then return {} end
    
    local options = {}
    
    if field_metadata.numeric then
        options = {
            { text = OPERATOR_TEXTS[OPERATORS.EQUALS], value = OPERATORS.EQUALS },
            { text = OPERATOR_TEXTS[OPERATORS.NOT_EQUALS], value = OPERATORS.NOT_EQUALS },
            { text = OPERATOR_TEXTS[OPERATORS.GREATER_THAN], value = OPERATORS.GREATER_THAN },
            { text = OPERATOR_TEXTS[OPERATORS.LESS_THAN], value = OPERATORS.LESS_THAN },
            { text = OPERATOR_TEXTS[OPERATORS.IS_EMPTY], value = OPERATORS.IS_EMPTY },
            { text = OPERATOR_TEXTS[OPERATORS.IS_NOT_EMPTY], value = OPERATORS.IS_NOT_EMPTY },
        }
    else
        options = {
            { text = OPERATOR_TEXTS[OPERATORS.EQUALS], value = OPERATORS.EQUALS },
            { text = OPERATOR_TEXTS[OPERATORS.CONTAINS], value = OPERATORS.CONTAINS },
            { text = OPERATOR_TEXTS[OPERATORS.STARTS_WITH], value = OPERATORS.STARTS_WITH },
            { text = OPERATOR_TEXTS[OPERATORS.ENDS_WITH], value = OPERATORS.ENDS_WITH },
            { text = OPERATOR_TEXTS[OPERATORS.NOT_EQUALS], value = OPERATORS.NOT_EQUALS },
            { text = OPERATOR_TEXTS[OPERATORS.NOT_CONTAINS], value = OPERATORS.NOT_CONTAINS },
            { text = OPERATOR_TEXTS[OPERATORS.IS_EMPTY], value = OPERATORS.IS_EMPTY },
            { text = OPERATOR_TEXTS[OPERATORS.IS_NOT_EMPTY], value = OPERATORS.IS_NOT_EMPTY },
        }
    end
    
    return options
end

-- Show dialog to create/edit smart collection rules
local function showSmartCollectionRulesDialog(collection_name, existing_rules)
    existing_rules = existing_rules or { combine_operator = "AND" }
    
    local rules = {}
    for i, rule in ipairs(existing_rules) do
        table.insert(rules, {
            field = rule.field,
            operator = rule.operator,
            value = rule.value,
        })
    end
    
    local combine_operator = existing_rules.combine_operator or "AND"
    
    local rules_menu
    
    -- Forward declarations
    local showAddRuleDialog
    local showEditRuleDialog
    local showOperatorDialog
    local showValueDialog
    local saveRules
    local testRules
    
    local function updateRulesMenu()
        local item_table = {}
        
        -- Add combine operator selector
        table.insert(item_table, {
            text = T(_("Combine conditions: %1"), combine_operator == "AND" and _("All (AND)") or _("Any (OR)")),
            callback = function()
                combine_operator = combine_operator == "AND" and "OR" or "AND"
                updateRulesMenu()
            end,
            separator = true,
        })
        
        -- Add existing rules
        for i, rule in ipairs(rules) do
            local field_text = METADATA_FIELDS[rule.field] and METADATA_FIELDS[rule.field].text or rule.field
            local operator_text = OPERATOR_TEXTS[rule.operator] or rule.operator
            local value_text = rule.value or ""
            if rule.operator == OPERATORS.IS_EMPTY or rule.operator == OPERATORS.IS_NOT_EMPTY then
                value_text = ""
            end
            
            table.insert(item_table, {
                text = T(_("%1 %2 %3"), field_text, operator_text, value_text),
                callback = function()
                    showEditRuleDialog(i, rule)
                end,
            })
        end
        
        -- Add "Add rule" button
        table.insert(item_table, {
            text = _("Add rule"),
            callback = function()
                showAddRuleDialog()
            end,
            separator = #rules > 0,
        })
        
        -- Add "Save" button
        if #rules > 0 then
            table.insert(item_table, {
                text = _("Save rules"),
                callback = function()
                    saveRules()
                end,
                separator = true,
            })
        end
        
        -- Add "Test rules" button
        if #rules > 0 then
            table.insert(item_table, {
                text = _("Test rules (update collection)"),
                callback = function()
                    testRules()
                end,
            })
        end
        
        rules_menu:switchItemTable(_("Smart Collection Rules"), item_table)
    end
    
    showAddRuleDialog = function()
        showEditRuleDialog(nil, nil)
    end
    
    showEditRuleDialog = function(rule_index, rule)
        rule = rule or {}
        
        -- Field selection
        local field_items = {}
        for field, metadata in pairs(METADATA_FIELDS) do
            table.insert(field_items, {
                text = metadata.text,
                callback = function()
                    UIManager:close(rules_menu)
                    showOperatorDialog(rule_index, field, rule.operator, rule.value)
                end,
            })
        end
        
        local field_menu = Menu:new{
            title = _("Select field"),
            item_table = field_items,
            covers_fullscreen = true,
        }
        UIManager:show(field_menu)
    end
    
    showOperatorDialog = function(rule_index, field, operator, value)
        operator = operator or OPERATORS.CONTAINS
        value = value or ""
        
        local operator_items = {}
        local operator_options = getOperatorOptions(field)
        
        for _, opt in ipairs(operator_options) do
            table.insert(operator_items, {
                text = opt.text,
                callback = function()
                    UIManager:close(operator_menu)
                    showValueDialog(rule_index, field, opt.value, value)
                end,
            })
        end
        
        local operator_menu = Menu:new{
            title = T(_("Select operator for %1"), METADATA_FIELDS[field].text),
            item_table = operator_items,
            covers_fullscreen = true,
        }
        UIManager:show(operator_menu)
    end
    
    showValueDialog = function(rule_index, field, operator, value)
        value = value or ""
        
        -- For IS_EMPTY and IS_NOT_EMPTY, no value needed
        if operator == OPERATORS.IS_EMPTY or operator == OPERATORS.IS_NOT_EMPTY then
            local new_rule = {
                field = field,
                operator = operator,
                value = "",
            }
            
            if rule_index then
                rules[rule_index] = new_rule
            else
                table.insert(rules, new_rule)
            end
            
            UIManager:close(rules_menu)
            rules_menu = Menu:new{
                title = _("Smart Collection Rules"),
                item_table = {},
                covers_fullscreen = true,
                onClose = function()
                    updateRulesMenu()
                end,
            }
            UIManager:show(rules_menu)
            updateRulesMenu()
            return
        end
        
        local field_metadata = METADATA_FIELDS[field]
        local input_hint = field_metadata.numeric and "123" or _("Enter value")
        
        -- Create dialog with buttons - value_dialog will be captured in closure
        local value_dialog
        value_dialog = InputDialog:new{
            title = T(_("Enter value for %1"), METADATA_FIELDS[field].text),
            input = value,
            input_hint = input_hint,
            buttons = {{
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(value_dialog)
                    end,
                },
                {
                    text = _("Save"),
                    callback = function()
                        if not value_dialog then return end
                        local input_value = value_dialog:getInputText()
                        local new_rule = {
                            field = field,
                            operator = operator,
                            value = input_value,
                        }
                        
                        if rule_index then
                            rules[rule_index] = new_rule
                        else
                            table.insert(rules, new_rule)
                        end
                        
                        UIManager:close(value_dialog)
                        UIManager:close(rules_menu)
                        rules_menu = Menu:new{
                            title = _("Smart Collection Rules"),
                            item_table = {},
                            covers_fullscreen = true,
                        }
                        UIManager:show(rules_menu)
                        updateRulesMenu()
                    end,
                },
            }},
        }
        UIManager:show(value_dialog)
        value_dialog:onShowKeyboard()
    end
    
    saveRules = function()
        if #rules == 0 then
            UIManager:show(InfoMessage:new{
                text = _("Please add at least one rule"),
            })
            return
        end
        
        local all_rules = loadSmartCollectionRules()
        all_rules[collection_name] = {
            combine_operator = combine_operator,
        }
        for i, rule in ipairs(rules) do
            table.insert(all_rules[collection_name], rule)
        end
        
        saveSmartCollectionRules(all_rules)
        
        -- Update collection immediately
        updateSmartCollection(collection_name, all_rules[collection_name])
        
        UIManager:close(rules_menu)
        UIManager:show(InfoMessage:new{
            text = _("Smart collection rules saved and collection updated"),
        })
    end
    
    testRules = function()
        if #rules == 0 then
            UIManager:show(InfoMessage:new{
                text = _("Please add at least one rule"),
            })
            return
        end
        
        local test_rules = {
            combine_operator = combine_operator,
        }
        for i, rule in ipairs(rules) do
            table.insert(test_rules, rule)
        end
        
        local count = updateSmartCollection(collection_name, test_rules)
        local message
        if count == 0 then
            message = _("Collection updated. No books matched the rules.")
        else
            message = T(_("Collection updated. %1 books added or removed."), count)
        end
        UIManager:show(InfoMessage:new{
            text = message,
        })
    end
    
    rules_menu = Menu:new{
        title = _("Smart Collection Rules"),
        item_table = {},
        covers_fullscreen = true,
    }
    UIManager:show(rules_menu)
    updateRulesMenu()
end

-- Patch FileManagerCollection to add smart collection marker and menu
local orig_getCollMarker = FileManagerCollection.getCollMarker
function FileManagerCollection.getCollMarker(coll_name)
    local marker = orig_getCollMarker(coll_name)
    if isSmartCollection(coll_name) then
        marker = marker and (marker .. " " .. SMART_COLLECTION_MARKER) or SMART_COLLECTION_MARKER
    end
    return marker
end

-- Patch onCollListHold to add "Make smart collection" option
local orig_onCollListHold = FileManagerCollection.onCollListHold
function FileManagerCollection:onCollListHold(item)
    if self._manager.selected_collections then -- select mode
        return orig_onCollListHold(self, item)
    end
    
    local is_smart = isSmartCollection(item.name)
    local button_dialog
    local buttons = {}
    
    -- Add smart collection option at the top
    table.insert(buttons, {
        {
            text = is_smart and _("Edit smart collection rules") or _("Make smart collection"),
            callback = function()
                UIManager:close(button_dialog)
                if is_smart then
                    local rules = loadSmartCollectionRules()
                    showSmartCollectionRulesDialog(item.name, rules[item.name])
                else
                    -- Check if collection has folders connected
                    local coll_settings = ReadCollection.coll_settings[item.name]
                    if not coll_settings.folders or next(coll_settings.folders) == nil then
                        UIManager:show(InfoMessage:new{
                            text = _("Please connect at least one folder to the collection first"),
                        })
                        return
                    end
                    showSmartCollectionRulesDialog(item.name)
                end
            end,
        },
    })
    
    -- Add separator if smart collection option was added
    if is_smart then
        table.insert(buttons, {
            {
                text = _("Remove smart collection rules"),
                callback = function()
                    UIManager:close(button_dialog)
                    UIManager:show(ConfirmBox:new{
                        text = _("Remove smart collection rules? The collection will become a regular collection."),
                        ok_text = _("Remove"),
                        ok_callback = function()
                            local all_rules = loadSmartCollectionRules()
                            all_rules[item.name] = nil
                            saveSmartCollectionRules(all_rules)
                            UIManager:show(InfoMessage:new{
                                text = _("Smart collection rules removed"),
                            })
                        end,
                    })
                end,
            },
        })
    end
    
    -- Add separator before original buttons
    if #buttons > 0 then
        table.insert(buttons, {}) -- separator
    end
    
    -- Add original buttons
    table.insert(buttons, {
        {
            text = _("Filter new books"),
            callback = function()
                UIManager:close(button_dialog)
                self._manager:showCollFilterDialog(item)
            end,
        },
        {
            text = _("Connect folders"),
            callback = function()
                UIManager:close(button_dialog)
                self._manager:showCollFolderList(item)
            end,
        },
    })
    
    if item.name ~= ReadCollection.default_collection_name then
        table.insert(buttons, {
            {
                text = _("Remove collection"),
                callback = function()
                    UIManager:close(button_dialog)
                    self._manager:removeCollection(item)
                end,
            },
            {
                text = _("Rename collection"),
                callback = function()
                    UIManager:close(button_dialog)
                    self._manager:renameCollection(item)
                end,
            },
        })
    end
    
    button_dialog = ButtonDialog:new{
        title = item.text,
        title_align = "center",
        buttons = buttons,
    }
    UIManager:show(button_dialog)
    return true
end

-- Auto-update smart collections when books are added/modified
local FileManager = require("apps/filemanager/filemanager")
local orig_onBookMetadataChanged = FileManagerCollection.onBookMetadataChanged
function FileManagerCollection:onBookMetadataChanged(prop_updated)
    orig_onBookMetadataChanged(self, prop_updated)
    
    if prop_updated and prop_updated.filepath then
        -- Check if file is in any smart collections
        local file = prop_updated.filepath
        local collections = ReadCollection:getCollectionsWithFile(file)
        local rules = loadSmartCollectionRules()
        
        for coll_name in pairs(collections) do
            if rules[coll_name] then
                -- Re-evaluate and update if needed
                local book_props = prop_updated.doc_props or self.ui.bookinfo:getDocProps(file, nil, true)
                if book_props then
                    local matches = evaluateRules(book_props, rules[coll_name])
                    local is_in_collection = ReadCollection:isFileInCollection(file, coll_name)
                    
                    if matches and not is_in_collection then
                        ReadCollection:addItem(file, coll_name)
                        ReadCollection:write({ [coll_name] = true })
                    elseif not matches and is_in_collection then
                        ReadCollection:removeItem(file, coll_name)
                        ReadCollection:write({ [coll_name] = true })
                    end
                end
            end
        end
    end
end

-- Update smart collections when showing collection list
local orig_onShowCollList = FileManagerCollection.onShowCollList
function FileManagerCollection:onShowCollList(file_or_selected_collections, caller_callback, no_dialog)
    -- Auto-update all smart collections in background
    local Trapper = require("ui/trapper")
    Trapper:dismissableRunInSubprocess(function()
        updateAllSmartCollections()
    end)
    
    return orig_onShowCollList(self, file_or_selected_collections, caller_callback, no_dialog)
end

-- Register patch to get BookInfoManager from CoverBrowser plugin
userpatch.registerPatchPluginFunc("coverbrowser", function(CoverBrowser)
    -- Try to get BookInfoManager from the plugin
    if CoverBrowser.BookInfoManager then
        BookInfoManagerRef = CoverBrowser.BookInfoManager
        logDebug("Smart Collections: BookInfoManager loaded from CoverBrowser")
    else
        -- Try to require directly
        local success, bm = pcall(require, "bookinfomanager")
        if success and bm then
            BookInfoManagerRef = bm
            logDebug("Smart Collections: BookInfoManager loaded directly")
        end
    end
end)

logger.info("Smart Collections userpatch loaded")

-- Prevent KOReader's default folder syncing for smart collections
local orig_ReadCollection_updateCollectionFromFolder = ReadCollection.updateCollectionFromFolder
function ReadCollection:updateCollectionFromFolder(collection_name, folders, is_showing)
    if isSmartCollection(collection_name) then
        return 0
    end
    return orig_ReadCollection_updateCollectionFromFolder(self, collection_name, folders, is_showing)
end

