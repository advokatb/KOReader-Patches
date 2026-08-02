# KOReader User Patches by advokatb

A collection of user patches for KOReader that enhance functionality and customization.

**Tested on:** KOReader 2025.10 "Ghost" with Project: Title v3.5 and CoverBrowser plugin

## 🞂 How to install a user patch?

> [!IMPORTANT]
> Please [check the guide here](https://koreader.rocks/user_guide/#L2-userpatches) for detailed installation instructions.

---

<details>
<summary><strong>🞂 <a href="2-smart-collections.lua">2-smart-collections.lua</a></strong> - Smart Collections</summary>

## 🞂 [2-smart-collections.lua](2-smart-collections.lua)

**Smart Collections** - Automatic collections based on metadata rules (author, date, tags, series, language, etc.)

### Features

- **Rule-based filtering**: Create collections automatically based on book metadata
- **Multiple operators**: equals, contains, starts with, ends with, not equals, not contains, greater than, less than, is empty, is not empty
- **Combined conditions**: Use AND (all rules must match) or OR (any rule must match)
- **Automatic updates**: Collections are automatically updated when books are added or modified
- **Smart folder scanning**: Automatically scans subfolders if no books found in root folder
- **Visual indicator**: Smart collections are marked with a 💡 icon

### Supported Metadata Fields

- **Authors** (multi-value) - Check against author names
- **Title** - Filter by book title
- **Series** - Filter by series name
- **Keywords** (multi-value) - Filter by tags/keywords
- **Language** - Filter by book language
- **Publication date** - Filter by publication date
- **Pages** (numeric) - Filter by page count
- **Reading status** - Filter by reading status (New, Reading, On hold, Finished)
- **Rating** (numeric) - Filter by star rating (0 to 5)

### Installation

1. Copy `2-smart-collections.lua` to `koreader/patches/` folder
2. Restart KOReader

### Usage

1. **Create a collection** and connect at least one folder to it:
   - Go to **File Manager** → **Collections**
   - Create a new collection or use an existing one
   - Long-press on the collection → **Connect folders**
   - Select the folder(s) containing your books

2. **Make it a smart collection**:
   - Long-press on the collection in the collections list
   - Select **"Make smart collection"**

3. **Add rules**:
   - Select a field (e.g., Authors, Title, Series)
   - Choose an operator (e.g., contains, equals, starts with)
   - Enter the value to match (e.g., "Tolkien", "Harry Potter")
   - Add more rules if needed

4. **Choose how to combine rules**:
   - **All (AND)**: All rules must match
   - **Any (OR)**: At least one rule must match

5. **Save and test**:
   - Tap **"Save rules"** to save and update the collection
   - Or tap **"Test rules (update collection)"** to test without saving

### Example Rules

- **Authors contains "King"** - All books by authors containing "King"
- **Series equals "Harry Potter"** - All books in the Harry Potter series
- **Pages greater than 500** - All books with more than 500 pages
- **Language equals "en"** - All English books
- **Keywords contains "fantasy"** - All books tagged with "fantasy"
- **Reading status equals "Finished"** - All finished books
- **Reading status equals "Reading"** - All currently reading books
- **Reading status equals "On hold"** - All books on hold
- **Rating greater than 3** - All books with more than 3 stars

### Update Modes

Smart collections support two update modes:

- **Manual update** (default): Collections are only updated when you explicitly request it
- **Auto-update**: Collections are automatically updated every time the collection list opens

> [!IMPORTANT]
> **Why manual is the default:** Auto-update scans all files in connected folders for every smart collection. With many books or collections, this can cause noticeable delays when opening the collection list.

**To update collections manually:**
1. Long-press on any collection in the list
2. Tap **"Update this collection"** (for one collection) or **"Update all smart collections"** (for all)

**To enable/disable auto-update:**
1. Long-press on any collection in the list
2. Tap **"Auto-update: ON/OFF"** to toggle

### How It Works

- Smart collections scan connected folders for books
- Each book's metadata is checked against the defined rules
- Books matching the rules are automatically added to the collection
- Books that no longer match are automatically removed
- Collections are updated when:
  - Rules are saved
  - You manually trigger an update
  - Book metadata changes
  - Collection list is opened (only if auto-update is enabled)

### Notes

- Smart collections require at least one connected folder
- The patch uses BookInfoManager from CoverBrowser plugin (or loads it directly)
- Rules are stored in `koreader/settings/smart_collections.lua`
- KOReader's default “folder sync” (auto-adding every file from connected folders) is disabled for smart collections so that only rule-matching books remain
- Smart collections are marked with a 💡 icon in the collections list

### Debug logging

Verbose logging is disabled by default.  
If you need to troubleshoot rule matching, set:

```lua
local SMART_COLLECTIONS_DEBUG = true
```

near the top of `2-smart-collections.lua`.  

> [!WARNING]
> This enables detailed `logger.info` output (matched authors, rule checks, etc.). Remember to set it back to `false` once finished to avoid performance issues.

</details>

---

<details>
<summary><strong>🞂 <a href="2-pt-metadata-browser.lua">2-pt-metadata-browser.lua</a></strong> - Metadata Browser for Project: Title</summary>

## 🞂 [2-pt-metadata-browser.lua](2-pt-metadata-browser.lua)

**Metadata Browser for Project: Title** – adds a virtual "📚 Metadata" folder to the Project: Title file browser, allowing you to browse books by metadata (authors, series, genres, publication year, etc.) extracted from Calibre's book database.

### Features

- Adds a global `📚 Metadata` entry to File Manager (Project: Title modes)
- Browse books by **Authors**, **Series**, **Genres**, **Year**, and **Title**
- **Genres and Years** are automatically extracted from Calibre's `keywords` field
  - Pure numbers (e.g., "2023", "1999") are treated as years
  - Values containing letters (e.g., "Fantasy", "Sci-Fi") are treated as genres
- **Book count display**: Optionally show number of books next to each metadata value
- **Configurable**: Enable/disable individual metadata types, customize display order, filter genres, and more
- Uses book covers for metadata folder icons (stacked or grid layout)

### Installation

1. Copy `2-pt-metadata-browser.lua` to `koreader/patches/`
2. Restart KOReader

### Usage

1. Open File Manager (Project: Title must be enabled)
2. In your home directory, tap the `📚 Metadata` entry that appears at the top of the list
3. Select a metadata type (e.g., Author, Series, Genres, Year)
4. Choose a value from the list (e.g., an author name, genre, or year)

### Configuration

> [!NOTE]
> All settings are at the top of `2-pt-metadata-browser.lua` in the `CONFIGURATION SETTINGS` section:

- **Enable/disable metadata types**: Set `CONFIG_ENABLE_TITLE`, `CONFIG_ENABLE_AUTHOR`, `CONFIG_ENABLE_SERIES`, `CONFIG_ENABLE_GENRES`, `CONFIG_ENABLE_YEAR` to `false` to hide specific types
- **Custom display order**: Set `CONFIG_METADATA_ORDER = {"AUTHOR", "SERIES", "GENRES", "YEAR", "TITLE"}` to customize the order
- **Show book counts**: Set `CONFIG_SHOW_BOOK_COUNT = true` to display "(N)" next to each value
- **Hide empty values**: Set `CONFIG_HIDE_EMPTY_VALUES = true` (default) to filter out empty/null metadata
- **Genre filtering**: Use `CONFIG_GENRE_WHITELIST` and `CONFIG_GENRE_BLACKLIST` to control which genres are shown
- **Case sensitivity**: Set `CONFIG_CASE_SENSITIVE_GENRES = true` for case-sensitive genre matching
- **Custom symbols**: Override default icons for each metadata type using `CONFIG_TITLE_SYMBOL`, `CONFIG_AUTHOR_SYMBOL`, etc.

### Database

The patch reads metadata from KOReader's bookinfo cache database:
- **Project: Title**: `DataStorage:getSettingsDir() .. "/PT_bookinfo_cache.sqlite3"`
- **CoverBrowser**: `DataStorage:getSettingsDir() .. "/coverbrowser_bookinfo_cache.sqlite3"`

> [!NOTE]
> The `keywords` field in the `bookinfo` table contains newline-separated values (genres, years, etc.) that are automatically parsed and categorized.

### Notes

- The virtual entry is shown only at the top level (home folder) to keep subfolders uncluttered
- The virtual folder exists only inside the UI; no files/folders are created on disk
- Based on `2-pt-collections.lua` (virtual folder structure) and `2-BrowseByMetadata.lua` (metadata browsing functionality)

</details>

---

<details>
<summary><strong>🞂 <a href="2-pt-collections.lua">2-pt-collections.lua</a></strong> - Collections View for Project: Title</summary>

## 🞂 [2-pt-collections.lua](2-pt-collections.lua)

**Collections View for Project: Title** – adds a virtual "✪ Collections" folder inside the Project: Title file browser so you can browse KOReader collections as if they were directories.

### Features

- Adds a global `✪ Collections` entry to File Manager (Project: Title modes)
- Lists every KOReader collection as a folder with book counts
- Entering a collection shows all of its books; tapping opens the book instantly
- Works with both Grid and List layouts, respects sorting/filtering
- **Automatic display mode switching**: Applies your Project: Title "Collections display mode" setting when viewing collections, and restores your regular file browser mode when exiting
- Automatically refreshes whenever collections change
- Uses `icons/folder.collections.svg` if present (custom folder icon included in repo), or uses `icons/folder.collections.svg` if present, otherwise displays books from the collections identical to Project Title display (grid or stack)
- Each collection can have different png or svg icons by defining a `icons/_collection-name_.folder` SVG or PNG file.
  - e.g. `icons/Favorites.folder.png`

  ![In Home Folder](screenshots/Home-Folder.png)

  ![Inside Collections Folder](screenshots/Collection-Folder.png)

### Installation

1. Copy `2-pt-collections.lua` to `koreader/patches/`
2. Restart KOReader

### Usage

1. Open File Manager (Project: Title must be enabled)
2. In your home directory, tap the `✪ Collections` entry that appears at the top of the list
3. The view automatically switches to your configured "Collections display mode"
4. Pick a collection folder to see the books it contains
5. Tap a book to open it, or use KOReader's standard long-press actions
6. When you navigate out, the view automatically returns to your normal file browser display mode

> [!TIP]
> You can configure the Collections display mode separately from your file browser mode in **Menu → Project: Title settings → Collections display mode** (Cover Grid, Cover List, Details List, or Filenames List).

### Configuration

- **Hide Favorites collection**: Edit `2-pt-collections.lua` and set `SHOW_FAVORITES_COLLECTION = false` (default) to hide the built-in Favorites collection from the Collections view. Set to `true` to show it.

### Notes

- The virtual entry is shown only at the top level (home folder) to keep subfolders uncluttered
- The virtual folder exists only inside the UI; no files/folders are created on disk
- When sorting by "last read date", collections are ordered based on the most recently accessed book within each collection

</details>

---

<details>
<summary><strong>🞂 <a href="2-custom-folder-fonts.lua">2-custom-folder-fonts.lua</a></strong> - Custom Folder Fonts</summary>

## 🞂 [2-custom-folder-fonts.lua](2-custom-folder-fonts.lua)

**Custom Folder Fonts** - Custom font selection for folder names in Project: Title plugin.

### Features

- **Custom Font Selection**: Choose any TrueType (.ttf) or OpenType (.otf) font from your `koreader/fonts/` folder
- **Font Size Adjustment**: Six size presets from Tiny to Huge
- **Automatic Font Discovery**: Recursively scans all fonts in `koreader/fonts/` including subdirectories
- **Works in All Modes**: Both Cover Grid (mosaic) and List view
- **Clean Integration**: Adds new "Folder Fonts" section in Advanced Settings

### Installation

1. Place your custom font files in `koreader/fonts/` folder on your device
   > [!TIP]
   > You can organize fonts in subdirectories (e.g., `fonts/Atkinson_Hyperlegible/`)
   - Supported formats: `.ttf` and `.otf`

2. Copy `2-custom-folder-fonts.lua` to `koreader/patches/` folder

3. Restart KOReader

### Usage

1. Open **File Manager**
2. Tap **⚙ Settings** → **Project: Title settings**
3. Navigate to **Advanced settings** → **Folder Fonts**
4. Select **Custom font** and choose your desired font from the list
5. Optionally adjust **Font size** (Tiny to Huge)
6. Restart KOReader when prompted

### How It Works

This patch modifies the `ptutil.good_serif` and `ptutil.good_sans` font paths that Project: Title uses for rendering folder names. The font change applies to:

- Folder names in Cover Grid (mosaic) view
- Folder names in List view
- Both serif and sans-serif contexts

<details>
<summary><h3>Font Size Presets & Recommended Fonts</h3></summary>

### Font Size Presets

| Preset | Adjustment | Best For |
|--------|------------|----------|
| Tiny | -4 | Maximum density, small screens |
| Small | -2 | Slightly more compact |
| Default | 0 | Standard Project: Title size |
| Large | +2 | Better readability |
| Extra Large | +4 | High visibility |
| Huge | +6 | Maximum readability |

### Recommended Fonts

#### Highly Readable Fonts
- **Atkinson Hyperlegible** - Designed for low vision readers
- **OpenDyslexic** - Optimized for dyslexia
- **Lexend** - Improves reading proficiency

#### Clean Sans-Serif Fonts
- **Inter** - Modern, excellent at small sizes
- **Source Sans 3** - Adobe's workhorse
- **Roboto** - Google's Material Design font

#### Elegant Serif Fonts
- **Source Serif 4** - Pairs with Source Sans
- **Crimson Pro** - Classic book typography
- **Literata** - Designed for e-readers

### Settings Storage
- Font path: `custom_folder_font` in BookInfoManager
- Size adjustment: `custom_folder_font_size` in BookInfoManager

</details>

> [!NOTE]
> This patch only affects folder names in Project: Title. It does not change:
> - Book titles
> - UI fonts
> - Reader fonts
> - Footer text (path display at bottom)

</details>

---

<details>
<summary><strong>🞂 <a href="2-pt-book-spine-effect.lua">2-pt-book-spine-effect.lua</a></strong> - Book Spine Effect (Apple Books style)</summary>

## 🞂 [2-pt-book-spine-effect.lua](2-pt-book-spine-effect.lua)

**Book Spine Effect (Apple Books style)** - Adds a pressed book spine shadow effect to book covers in Project: Title view, similar to Apple Books.

### Features

- **Apple Books-style effect**: Creates a subtle shadow/gradient along the left edge of book covers to simulate a pressed spine
- **SVG support**: Uses custom SVG icon (`book.spine.svg`) if available in `icons/` folder, otherwise uses programmatic gradient
- **Fully configurable**: Three adjustable settings for shadow width, intensity, and offset from edge
- **Automatic scaling**: SVG icon automatically scales to match cover height
- **Works with all covers**: Applies to all book covers in Project: Title view

### Installation

1. Copy `2-pt-book-spine-effect.lua` to `koreader/patches/` folder
2. (Optional) Copy `icons/book.spine.svg` to `koreader/icons/` for custom SVG effect
3. Restart KOReader

### Usage

The effect is automatically applied to all book covers. Configure it via:

1. Open **File Manager**
2. Tap **⚙ Settings** → **File browser settings**
3. Navigate to **Project: Title Settings** → **Advanced settings** → **Book Spine Effect**
4. Adjust settings:
   - **Shadow width**: Small, Medium, Large, Extra Large
   - **Shadow intensity**: Light, Medium, Dark, Very Dark
   - **Offset from edge**: Small, Medium, Large, Extra Large

### Custom SVG Icon

You can use a custom SVG icon for the spine effect:

1. Create or edit `book.spine.svg` in `koreader/icons/` folder
2. The SVG should be vertical (height > width) with a gradient from dark (left) to transparent (right)
3. The icon will automatically scale to match cover height

### Settings Storage

- Shadow width: `pt_spine_shadow_width` in BookInfoManager
- Shadow intensity: `pt_spine_shadow_intensity` in BookInfoManager
- Left offset: `pt_spine_left_offset` in BookInfoManager

### Notes

- Only affects book covers, not folders
- Effect is always enabled (no on/off toggle)
- Inspired by [this issue](https://github.com/SeriousHornet/KOReader.patches/issues/8) by [@eduardorodrigues08](https://github.com/eduardorodrigues08)

> [!NOTE]
> Effect is always enabled (no on/off toggle).

  ![In Home Folder](screenshots/pt-book-spine-effect.png)

</details>

---

<details>
<summary><strong>🞂 <a href="2-pt-filter-folders-by-status.lua">2-pt-filter-folders-by-status.lua</a></strong> - Filter Folders by Book Status</summary>

## 🞂 [2-pt-filter-folders-by-status.lua](2-pt-filter-folders-by-status.lua)

**Filter Folders by Book Status** - Automatically hides folders that don't contain books matching your active book status filter (New, Reading, On hold, Finished) in Project: Title file browser.

### Features

- **Automatic folder filtering**: When you filter books by status, folders with no matching books are automatically hidden
- **Recursive scanning**: Checks subdirectories to ensure parent folders with matching books deep inside remain visible
- **Auto-loads on startup**: Remembers and applies your last filter selection when KOReader starts
- **Safe navigation**: Always preserves "Go Up" (⬆ ../) navigation item to prevent crashes
- **Real-time updates**: When you change a book's status, the folder visibility updates immediately

### Installation

1. Copy `2-pt-filter-folders-by-status.lua` to `koreader/patches/` folder
2. Restart KOReader

### Usage

1. Open **File Manager** (Project: Title must be enabled)
2. Tap **⚙ Settings** → **File browser settings** → **Book status**
3. Select a status filter (e.g., "New", "Reading")
4. Navigate to your books folder - only folders containing books with the selected status will be visible
5. To see all folders again, select "All" in the Book status filter

### How It Works

When a book status filter is active (e.g., "New"):
1. For each folder in the current directory, the patch recursively scans all files inside
2. If at least one book matches the selected status, the folder is shown
3. If no books match, the folder is hidden
4. The filter state is saved and automatically restored on next KOReader startup

### Notes

- Works only in normal folder browsing mode (not in metadata browser or collections view)
- The patch uses `BookList.getBookStatus()` to check each book's reading status
- If all items would be filtered out (edge case), the original list is returned to prevent crashes

> [!NOTE]
> Performance: The first time you enter a folder with the filter active, there may be a slight delay while scanning subdirectories.

</details>

---

<details>
<summary><strong>🞂 <a href="2-cyrillic-transliteration-reverter.lua">2-cyrillic-transliteration-reverter.lua</a></strong> - Cyrillic Transliteration Reverter</summary>

## 🞂 [2-cyrillic-transliteration-reverter.lua](2-cyrillic-transliteration-reverter.lua)

**Cyrillic Transliteration Reverter** - Automatically converts transliterated text back to Cyrillic for folder names displayed by Project: Title plugin in file manager only.

### Features

- **Automatic conversion**: Detects and converts transliterated Russian text back to Cyrillic script
- **Comprehensive rules**: Based on ISO 9 (GOST 7.79-2000), ALA-LC, and common transliteration patterns
- **File manager only**: Only affects folder names in file manager, not other menus
- **Smart detection**: Only processes text that looks like transliterated Russian
- **Virtual folders support**: Excludes virtual Collections and Metadata folders from transliteration
- **Proper sorting**: Folders are sorted by their Cyrillic (transliterated) names, ensuring correct alphabetical order

### Installation

1. Copy `2-cyrillic-transliteration-reverter.lua` to `koreader/patches/` folder
2. Restart KOReader

### Usage

The patch works automatically - no configuration needed. When Calibre sends books with transliterated folder names (like "Briendon Sandierson" instead of "Брендон Сандерсон"), the patch will automatically detect and convert transliterated Russian text back to Cyrillic in the file browser while keeping the original folder structure intact.

### Examples

The patch automatically converts:
- `Briendon Sandierson` → `Брендон Сандерсон`
- `Dжордж Оруелл` → `Джордж Оруэлл`
- `Pom Iu Dzhin` → `Пом Ю Джин`
- `Dozory` → `Дозоры`
- `Portaly` → `Порталы`
- `Romany` → `Романы`

### How It Works

The patch automatically:
1. **Detects transliterated Russian text** using common patterns (ch, sh, zh, ya, yu, etc.)
2. **Converts using standard transliteration rules**:
   - Multi-character patterns: ch→ч, sh→ш, zh→ж, ya→я, yu→ю, etc.
   - Single character patterns: a→а, b→б, v→в, g→г, etc.
3. **Preserves folder structure** (keeps trailing slashes for folders)
4. **Only processes text that looks like transliterated Russian** - English text is left unchanged
5. **Excludes virtual folders** - Virtual folders (Collections and Metadata) injected by `2-pt-collections.lua` and `2-pt-metadata-collections.lua` are not transliterated
6. **Enables proper sorting** - Creates transliterated sort keys for folders, so they are sorted alphabetically by their Cyrillic names rather than Latin transliteration

### Sorting

The patch modifies KOReader's sorting functions to use transliterated (Cyrillic) names for sorting folders. This ensures that:
- Folders like "Briendon Sandierson" are sorted as "Брендон Сандерсон" in the correct Cyrillic alphabetical position
- All sorting modes (name, natural sorting, etc.) respect the transliterated order
- Mixed folders (some transliterated, some not) are sorted correctly

</details>