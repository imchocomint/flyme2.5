# FlyMe2TheMoon Game Data

This directory is where you place your original iOS game files so that the asset converter can prepare them for the Godot engine.

---

## Legal & Copyright Notice
This project is an open-source reimplementation engine for **FlyMe2TheMoon**.
Due to copyright, the original proprietary game assets (sprites, textures, audio sound effects, Box2D level geometry, scripts) created by miHoYo are **not** distributed with this repository. Players must provide their own copy of the iOS game data.

---

## Instructions

You can use either of the following methods:

### Method 1: Drop your `.ipa` or `.zip` file (Recommended / Easiest)
1. Place your `Fly2theMoon.ipa` (or `Fly2theMoon.zip`) into this `game_data/` folder (or into the root project folder).
2. Run `setup_game_data.bat` in the project root (or execute `python tools/setup_game_data.py`).
3. The script will automatically unpack textures from `.pvr.ccz`, convert Box2D collision coordinates, copy levels, and organize all assets into Godot format.

### Method 2: Drop extracted files
1. If you have extracted the IPA file, drop either:
   - The `Fly2theMoon.app` folder (or `Payload/Fly2theMoon.app`), OR
   - All the loose game files (`TextureS1.pvr.ccz`, `edgeData.dat`, `roleConfig.json`, `Level_001`, etc.) directly into this `game_data/` folder.
2. Run `setup_game_data.bat` in the project root (or execute `python tools/setup_game_data.py`).

---

After setup is complete, open the project in Godot Engine and enjoy!
