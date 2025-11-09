# Custom Folder Fonts for Project: Title

A user patch that enables custom font selection for folder names in KOReader's Project: Title plugin.

**Tested on:** KOReader 2025.10 "Ghost" with Project: Title v3.5

## 🞂 How to install a user patch?

Please [check the guide here](https://koreader.rocks/user_guide/#L2-userpatches) for detailed installation instructions.

## Features

- **Custom Font Selection**: Choose any TrueType (.ttf) or OpenType (.otf) font from your `koreader/fonts/` folder
- **Font Size Adjustment**: Six size presets from Tiny to Huge
- **Automatic Font Discovery**: Recursively scans all fonts in `koreader/fonts/` including subdirectories
- **Works in All Modes**: Both Cover Grid (mosaic) and List view
- **Clean Integration**: Adds new "Folder Fonts" section in Advanced Settings

## Installation

1. Place your custom font files in `koreader/fonts/` folder on your device
   - You can organize fonts in subdirectories (e.g., `fonts/Atkinson_Hyperlegible/`)
   - Supported formats: `.ttf` and `.otf`

2. Copy `2-custom-folder-fonts.lua` to `koreader/patches/` folder

3. Restart KOReader

## Usage

1. Open **File Manager**
2. Tap **⚙ Settings** → **Project: Title settings**
3. Navigate to **Advanced settings** → **Folder Fonts**
4. Select **Custom font** and choose your desired font from the list
5. Optionally adjust **Font size** (Tiny to Huge)
6. Restart KOReader when prompted

<details>
<summary><h2>Font Size Presets & Recommended Fonts</h2></summary>

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

---

**Note:** This patch only affects folder names in Project: Title. It does not change:
- Book titles
- UI fonts
- Reader fonts
- Footer text (path display at bottom)

