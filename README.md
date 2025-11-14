# KOReader User Patches by advokatb

A collection of user patches for KOReader that enhance functionality and customization.

**Tested on:** KOReader 2025.10 "Ghost" with Project: Title v3.5 and CoverBrowser plugin

## 🞂 How to install a user patch?

Please [check the guide here](https://koreader.rocks/user_guide/#L2-userpatches) for detailed installation instructions.

---

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

- **Authors contains "Кинг"** - All books by authors containing "Кинг"
- **Series equals "Harry Potter"** - All books in the Harry Potter series
- **Pages greater than 500** - All books with more than 500 pages
- **Language equals "en"** - All English books
- **Keywords contains "fantasy"** - All books tagged with "fantasy"

### How It Works

- Smart collections automatically scan connected folders for books
- Each book's metadata is checked against the defined rules
- Books matching the rules are automatically added to the collection
- Books that no longer match are automatically removed
- Collections are updated when:
  - Rules are saved
  - Book metadata changes
  - Collection list is opened (background update)

### Notes

- Smart collections require at least one connected folder
- The patch uses BookInfoManager from CoverBrowser plugin (or loads it directly)
- Rules are stored in `koreader/settings/smart_collections.lua`
- Smart collections are marked with a 💡 icon in the collections list

---

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
   - You can organize fonts in subdirectories (e.g., `fonts/Atkinson_Hyperlegible/`)
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

**Note:** This patch only affects folder names in Project: Title. It does not change:
- Book titles
- UI fonts
- Reader fonts
- Footer text (path display at bottom)

---

## Credits

Inspired by patches from:
- [SeriousHornet's Visual Overhaul Suite](https://github.com/SeriousHornet/KOReader.patches)
- [joshuacant's KOReader patches](https://github.com/joshuacant/KOReader.patches)
- sebdelsol and u/medinauta
