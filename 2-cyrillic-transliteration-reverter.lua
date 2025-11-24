--[[
    This user patch automatically converts transliterated text back to Cyrillic
    for folder names displayed by Project: Title plugin in file manager only.
    
    It uses comprehensive transliteration rules to automatically detect and convert
    transliterated Russian text back to Cyrillic script. This is useful when
    Calibre sends books with transliterated names that can't be changed, but
    you want to see the original Cyrillic names in the file browser.
    
    Example: "Briendon Sandierson" -> "Брендон Сандерсон"
             "Dжордж Оруелл" -> "Джордж Оруэлл"
--]]

local Menu = require("ui/widget/menu")
local BookList = require("ui/widget/booklist")
local FileChooser = require("ui/widget/filechooser")
local lfs = require("libs/libkoreader-lfs")
local _getMenuText_orig = Menu.getMenuText

-- Virtual Collections folder injected by 2-pt-collections.lua
-- uses the ✪ star symbol as part of its segment name. We keep it as-is.
local COLLECTIONS_SYMBOL = "\u{272A}"
local COLLECTIONS_SEGMENT = COLLECTIONS_SYMBOL .. " "

-- Virtual Metadata folder injected by 2-pt-metadata-collections.lua
-- uses the 📚 metadata symbol as part of its segment name. We keep it as-is.
local METADATA_SYMBOL = "\u{e257}"
local METADATA_SEGMENT = METADATA_SYMBOL .. " "

local function is_virtual_collections_entry(item, menu_text)
    if not item then
        return false
    end
    if item.is_pt_collections_entry then
        return true
    end
    -- Fall back to checking path/text for the special segment if the flag isn't available
    if item.path and item.path:find(COLLECTIONS_SEGMENT, 1, true) then
        return true
    end
    if menu_text and menu_text:find(COLLECTIONS_SEGMENT, 1, true) then
        return true
    end
    return false
end

local function is_virtual_metadata_entry(item, menu_text)
    if not item then
        return false
    end
    if item.is_pt_metadata_entry then
        return true
    end
    -- Fall back to checking path/text for the special segment if the flag isn't available
    if item.path and item.path:find(METADATA_SEGMENT, 1, true) then
        return true
    end
    if menu_text and menu_text:find(METADATA_SEGMENT, 1, true) then
        return true
    end
    return false
end

local function is_virtual_folder_entry(item, menu_text)
    return is_virtual_collections_entry(item, menu_text) or is_virtual_metadata_entry(item, menu_text)
end

-- Function to automatically convert transliterated text to Cyrillic
local function convert_transliteration(text)
    if not text or type(text) ~= "string" then
        return text
    end
    
    -- Check if the text ends with a slash (indicating it's a folder)
    local is_folder = text:match("/$")
    local base_text = is_folder and text:sub(1, -2) or text
    
    local result = base_text
    
    -- Complete transliteration table for Russian
    -- Based on ISO 9 (GOST 7.79-2000), ALA-LC, and common transliteration patterns
    -- IMPORTANT: Patterns are ordered from longest to shortest to avoid conflicts
    -- More specific/longer patterns must come first
    local transliteration_map = {
        -- Longest multi-character patterns first (8+ chars) - MUST be longest!
        { "ionnyie", "ённые" },   -- endings: "Izmienionnyie" -> "Изменённые" (MUST be before "ion")
        { "Ionnyie", "ённые" },   -- uppercase variant
        { "IONNYIE", "ённые" },   -- all uppercase variant
        { "iennyie", "енные" },   -- endings: "Dvurozhdiennyie" -> "Двурожденные"
        { "Iennyie", "енные" },   -- uppercase variant
        { "ionnymi", "ёнными" },  -- instrumental plural endings (MUST be before "ion")
        { "ennymi", "енными" },   -- instrumental plural endings
        
        -- 7-character patterns
        { "onnyie", "ённые" },    -- for cases without leading "i"
        { "ennyie", "енные" },    -- for cases without leading "i"
        
        -- 6-character patterns
        { "Shch", "Щ" },
        { "shch", "щ" },
        { "SCHCH", "ЩЩ" },        -- rare uppercase variant
        
        -- 5-character patterns (common suffixes and endings)
        { "iuzhie", "южие" },
        { "inghie", "ингие" },
        { "skiia", "ския" },      -- adjective endings
        { "skogo", "ского" },     -- genitive endings
        { "skomu", "скому" },     -- dative endings
        
        -- 4-character patterns
        { "iuz", "юз" },          -- for "S'iuzien" -> "Сьюзен"
        { "ingh", "инг" },        -- for "Kingh" -> "Кинг"
        { "Tsy", "Цы" },
        { "tsy", "цы" },
        { "skii", "ский" },       -- adjective endings
        { "skie", "ские" },       -- plural adjective
        { "skoi", "ской" },       -- feminine genitive
        { "skaia", "ская" },      -- feminine adjective
        { "skoe", "ское" },       -- neuter adjective
        
        -- 3-character patterns (multi-letter Cyrillic letters)
        { "Sh", "Ш" },
        { "sh", "ш" },
        { "Ch", "Ч" },
        { "ch", "ч" },
        { "Zh", "Ж" },
        { "zh", "ж" },
        { "Kh", "Х" },
        { "kh", "х" },
        { "Ts", "Ц" },
        { "ts", "ц" },
        { "Yu", "Ю" },
        { "yu", "ю" },
        { "Ya", "Я" },
        { "ya", "я" },
        { "Yo", "Ё" },
        { "yo", "ё" },
        -- Note: Iu, Ia, Io are handled in 2-character patterns section to ensure they come before single "I"
        { "E'", "Э" },            -- hard E (э) with apostrophe
        { "e'", "э" },
        
        -- Common syllable patterns and endings (3 chars)
        -- IMPORTANT: "iei" MUST come before "ie" to handle "Sierghiei" -> "Сергей"
        { "iei", "ей" },          -- MUST be before "ie" - "Sierghiei" -> "Сергей"
        { "Iei", "ей" },          -- uppercase variant (I-e-i)
        { "IEI", "ей" },          -- all uppercase variant
        { "iEi", "ей" },          -- mixed case
        { "IeI", "ей" },          -- mixed case
        { "iEI", "ей" },          -- mixed case
        { "iai", "яй" },          -- "ia" + "i" combination
        { "ien", "ен" },          -- for "Stivien" -> "Стивен" (MUST be before "ion" for proper endings)
        { "ion", "ён" },          -- for "Rozhdionnyi" -> "Рожденный" (but "ionnyie" handled first!)
        { "nyie", "ные" },        -- plural endings
        { "nyi", "ный" },         -- adjective endings
        { "nye", "ные" },         -- alternative spelling/feminine endings
        { "nykh", "ных" },        -- genitive/accusative/dative/prepositional plural
        { "ium", "юм" },          -- for "Diuma" -> "Дюма"
        -- NOTE: "iel" -> "ель" is handled specially below to avoid conflicts
        -- It should only apply in specific contexts (end of word, before soft sign)
        { "iia", "ия" },          -- for "Garsiia" -> "Гарсиа"
        { "iin", "инь" },         -- for "Tsysin'" -> "Цысинь"
        { "ian", "ян" },          -- for "Luk'ianienko" -> "Лукьяненко"
        { "ier", "ер" },          -- for "Sierghiei" -> "Сергей"
        { "ing", "инг" },         -- for "Roulingh" -> "Роулинг"
        { "ova", "ова" },         -- feminine surnames/possessive endings
        { "evo", "ево" },         -- possessive endings
        { "evy", "евы" },         -- possessive endings
        { "yna", "ына" },         -- feminine endings
        { "ina", "ина" },         -- feminine endings
        { "ago", "аго" },         -- genitive endings
        { "ogo", "ого" },         -- genitive/accusative endings
        { "omu", "ому" },         -- dative endings
        { "omy", "омы" },         -- instrumental plural
        { "ymi", "ыми" },         -- instrumental plural
        
        -- 2-character patterns (CRITICAL: must come before single characters)
        -- These MUST be first in this group to ensure they match before single "I"
        { "Iu", "Ю" },            -- MUST be FIRST in 2-char group to handle "Pom Iu" -> "Пом Ю"
        { "iu", "ю" },
        { "Ia", "Я" },            -- alternative before "I"
        { "ia", "я" },
        { "Io", "Ё" },            -- alternative before "I"
        { "io", "ё" },
        { "gh", "г" },            -- for "Vierghiezie" -> "Вергезе"
        { "ai", "ай" },           -- for "Uaild" -> "Уайлд"
        { "oi", "ой" },           -- for cases like "Geroi" -> "Герой"
        { "ui", "уй" },           -- for cases like "Sui" -> "Суй"
        { "ei", "ей" },           -- for cases like "Rei" -> "Рей"
        -- IMPORTANT: "ie" must come after longer patterns like "iei", "ien", etc.
        { "ie", "е" },            -- for "Briendon" -> "Брендон" (but AFTER "iei", "ien")
        { "ye", "е" },            -- alternative for initial "е" (ALA-LC style)
        { "Ye", "Е" },            -- alternative for initial "Е"
        { "yi", "ый" },           -- adjective/masculine/genitive endings
        { "ykh", "ых" },          -- genitive/accusative/prepositional plural
        { "ym", "ым" },           -- dative/instrumental plural/instrumental endings
        -- Consonant + "y" endings for plural nouns (must come before single "y" -> "й")
        -- These typically represent "ы" at end of words like "Dozory" -> "Дозоры"
        { "ry", "ры" },           -- "Dozory" -> "Дозоры", "Portaly" -> "Порталы" (before single "y")
        { "ly", "лы" },           -- "Portaly" -> "Порталы"
        { "ny", "ны" },           -- "Romany" -> "Романы" (but AFTER "nyi", "nye", "nykh", "nymi")
        { "ty", "ты" },           -- plural endings
        { "sy", "сы" },           -- plural endings
        { "my", "мы" },           -- plural endings (but can be "my" -> "мы" as pronoun)
        { "by", "бы" },           -- plural endings
        { "vy", "вы" },           -- plural endings
        { "gy", "гы" },           -- plural endings
        { "dy", "ды" },           -- plural endings
        { "zy", "зы" },           -- plural endings
        { "ky", "кы" },           -- plural endings
        { "py", "пы" },           -- plural endings
        { "fy", "фы" },           -- plural endings
        { "yu", "ю" },            -- additional variant
        { "ya", "я" },            -- additional variant
        { "yo", "ё" },            -- additional variant
        { "ar'", "арь" },         -- for "Chubar'ian" -> "Чубарян"
        { "er'", "ерь" },         -- soft sign endings
        { "ir'", "ирь" },         -- soft sign endings
        { "or'", "орь" },         -- soft sign endings
        { "ur'", "урь" },         -- soft sign endings
        { "yr'", "ырь" },         -- soft sign endings
        { "''", "ъ" },            -- hard sign (alternative notation)
        { "'", "ь" },             -- soft sign
        
        -- Single character patterns
        { "A", "А" },
        { "a", "а" },
        { "B", "Б" },
        { "b", "б" },
        { "V", "В" },
        { "v", "в" },
        { "G", "Г" },
        { "g", "г" },
        { "D", "Д" },
        { "d", "д" },
        { "E", "Е" },
        { "e", "е" },
        { "Z", "З" },
        { "z", "з" },
        { "I", "И" },
        { "i", "и" },
        { "Y", "Й" },
        { "y", "й" },
        { "K", "К" },
        { "k", "к" },
        { "L", "Л" },
        { "l", "л" },
        { "M", "М" },
        { "m", "м" },
        { "N", "Н" },
        { "n", "н" },
        { "O", "О" },
        { "o", "о" },
        { "P", "П" },
        { "p", "п" },
        { "R", "Р" },
        { "r", "р" },
        { "S", "С" },
        { "s", "с" },
        { "T", "Т" },
        { "t", "т" },
        { "U", "У" },
        { "u", "у" },
        { "F", "Ф" },
        { "f", "ф" },
        -- Note: X is handled as "Kh/kh", Ц as "Ts/ts"
        -- Э is usually transliterated as "E" only in specific contexts,
        -- so it's handled contextually or through multi-character patterns
    }
    
    -- Apply transliteration patterns
    -- CRITICAL: Sort patterns by length (longest first) and apply in that exact order
    -- This ensures longer patterns always take priority over shorter ones
    
    -- First, sort all patterns by length (descending), then by position in original list
    local sorted_patterns = {}
    for i, pattern in ipairs(transliteration_map) do
        table.insert(sorted_patterns, {pattern = pattern, length = #pattern[1], index = i})
    end
    table.sort(sorted_patterns, function(a, b)
        if a.length ~= b.length then
            return a.length > b.length  -- Longer first
        end
        return a.index < b.index  -- If same length, preserve original order
    end)
    
    -- CRITICAL: Handle "Iu" pattern FIRST, before any other processing
    -- This must be done as a special case to avoid "I" being processed before "Iu"
    -- Use simple replacement first, then handle word boundaries
    result = result:gsub("Iu", "Ю")  -- Replace all "Iu" -> "Ю" first
    result = result:gsub("iu", "ю")  -- Replace all "iu" -> "ю"
    
    -- CRITICAL: Handle consonant + "y" endings at end of words BEFORE single "y" -> "й"
    -- This fixes cases like "Dozory" -> "Дозоры", "Portaly" -> "Порталы", "Romany" -> "Романы"
    -- Only replace if "y" is at end of word or followed by non-letter character
    result = result:gsub("([bcdfghklmnprstvzBCDFGHKLMNPRSTVZ])y([^%w])", "%1ы%2")  -- consonant + y + non-word
    result = result:gsub("([bcdfghklmnprstvzBCDFGHKLMNPRSTVZ])y$", "%1ы")         -- consonant + y at end
    
    -- CRITICAL: Handle "iel" -> "ель" ONLY in specific contexts (end of word, before soft sign)
    -- This prevents "iel" from matching in words like "Pienielopa" or "Korielli"
    -- where it should be "ie" -> "е" + "л"
    -- Apply "iel" -> "ель" only at end of word or before soft sign
    result = result:gsub("iel'([^%w]?)", "ель'%1")  -- "iel'" at end or before non-word
    result = result:gsub("iel([^%w]?)$", "ель%1")  -- "iel" at end of word
    result = result:gsub("Iel'([^%w]?)", "Ель'%1")  -- uppercase variant
    result = result:gsub("Iel([^%w]?)$", "Ель%1")  -- uppercase variant at end
    
    -- Now apply all patterns in sorted order (longest to shortest)
    -- This guarantees that longer patterns (like "ionnyie") are processed before shorter ones (like "ion")
    for _, entry in ipairs(sorted_patterns) do
        local pattern = entry.pattern
        -- Skip "Iu" patterns since we already handled them above
        if pattern[1] ~= "Iu" and pattern[1] ~= "iu" then
            -- Use plain string replacement - gsub will replace all occurrences
            result = result:gsub(pattern[1], pattern[2])
        end
    end
    
    -- If we made changes, return the result
    if result ~= base_text then
        return result .. (is_folder and "/" or "")
    end
    
    -- If no changes made, return original text
    return text
end

-- Helper function to get transliterated text for sorting (without trailing slash)
local function get_transliterated_sort_text(text)
    if not text or type(text) ~= "string" then
        return text
    end
    -- Remove trailing slash for sorting
    local text_for_sort = text:gsub("/$", "")
    local transliterated = convert_transliteration(text_for_sort)
    -- Remove trailing slash if it was added back
    return transliterated:gsub("/$", "")
end

-- Override FileChooser.getListItem to add sort_text for folders
local _getListItem_orig = FileChooser.getListItem
function FileChooser:getListItem(dirpath, f, fullpath, attributes, collate)
    local item = _getListItem_orig(self, dirpath, f, fullpath, attributes, collate)
    
    -- Add sort_text for folders (directories) to enable proper sorting with transliteration
    if item and not item.is_file then
        local is_directory = false
        if item.path then
            local mode = lfs.attributes(item.path, "mode")
            is_directory = mode == "directory"
        elseif item.file then
            local mode = lfs.attributes(item.file, "mode")
            is_directory = mode == "directory"
        elseif item.text and item.text:match("/$") then
            is_directory = true
        end
        
        if is_directory then
            local original_text = item.text:gsub("/$", "")  -- Remove trailing slash
            local skip_transliteration = is_virtual_folder_entry(item, item.text)
            if not skip_transliteration then
                -- Create sort_text with transliterated version for proper sorting
                item.sort_text = get_transliterated_sort_text(original_text)
            else
                -- For virtual folders (Collections/Metadata), use original text for sorting
                item.sort_text = original_text
            end
        end
    end
    
    return item
end

-- Override the getMenuText function
Menu.getMenuText = function(item)
    local menu_text = _getMenuText_orig(item)
    if menu_text then
        -- Only apply transliteration conversion for folders in file manager
        -- Check if this is a folder by looking for trailing slash or folder properties
        local is_directory = false
        if item then
            -- Check for trailing slash (indicates folder)
            if menu_text:match("/$") then
                is_directory = true
            -- Check if item.is_file indicates it's not a directory
            elseif item.is_file then
                is_directory = false
            -- Check path or file attributes using lfs
            elseif item.path then
                local mode = lfs.attributes(item.path, "mode")
                is_directory = mode == "directory"
            elseif item.file then
                local mode = lfs.attributes(item.file, "mode")
                is_directory = mode == "directory"
            end
        end
        
        local skip_transliteration = is_virtual_folder_entry(item, menu_text)
        if is_directory and not skip_transliteration then
            menu_text = convert_transliteration(menu_text)
        end
    end
    return menu_text
end

-- Modify collates to use sort_text for sorting if available
-- This ensures folders are sorted by their transliterated (Cyrillic) names
local ffiUtil = require("ffi/util")
for collate_name, collate in pairs(BookList.collates) do
    if collate.init_sort_func then
        local orig_init_sort_func = collate.init_sort_func
        collate.init_sort_func = function(cache)
            local orig_sort_func, new_cache = orig_init_sort_func(cache)
            return function(a, b)
                -- Temporarily replace text with sort_text for folders that have it
                -- This allows sorting to use transliterated (Cyrillic) names
                local orig_text_a, orig_text_b = a.text, b.text
                if a.sort_text then
                    a.text = a.sort_text
                end
                if b.sort_text then
                    b.text = b.sort_text
                end
                local result = orig_sort_func(a, b)
                -- Restore original text
                a.text = orig_text_a
                b.text = orig_text_b
                return result
            end, new_cache
        end
    end
end
