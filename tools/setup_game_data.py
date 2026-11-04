#!/usr/bin/env python3
"""
FlyMe2TheMoon - Automated Game Data Setup & Asset Extractor

Allows end-users to drop:
  1) An .ipa file (e.g. game_data/Fly2theMoon.ipa or *.ipa)
  2) An extracted folder (e.g. game_data/Payload/Fly2theMoon.app or game_data/...)
into the `game_data/` directory or project root.

This script automatically extracts, converts PVRTC textures (.pvr.ccz/.pvr),
unpacks texture atlases, extracts Box2D collision geometry, levels, audio,
and places all game assets into `project/assets/` and `project/data/`.
"""

import os
import sys
import glob
import json
import zlib
import struct
import shutil
import zipfile
import plistlib
import subprocess

# Ensure dependencies are available
try:
    from PIL import Image
except ImportError:
    print("[*] Installing Pillow...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "Pillow"])
    from PIL import Image

try:
    import texture2ddecoder
except ImportError:
    print("[*] Installing texture2ddecoder...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "texture2ddecoder"])
    import texture2ddecoder

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PROJECT_DIR = os.path.join(ROOT_DIR, "project")
ASSETS_DIR = os.path.join(PROJECT_DIR, "assets")
SPRITES_DIR = os.path.join(ASSETS_DIR, "sprites")
AUDIO_DIR = os.path.join(ASSETS_DIR, "audio")
DATA_DIR = os.path.join(PROJECT_DIR, "data")
LEVELS_DIR = os.path.join(DATA_DIR, "levels")
GAME_DATA_DIR = os.path.join(ROOT_DIR, "game_data")

def find_source_data():
    """
    Finds the original game data from:
      - .ipa or .zip archive in game_data/ or ROOT_DIR
      - Payload/Fly2theMoon.app or Fly2theMoon.app in game_data/ or source/
      - Direct loose files in game_data/ or any subfolder inside game_data/
    """
    # 1. Search if uncompressed data already exists in game_data/ or source/
    for search_root in [GAME_DATA_DIR, os.path.join(ROOT_DIR, "source")]:
        if not os.path.exists(search_root):
            continue
        for root, dirs, files in os.walk(search_root):
            if "roleConfig.json" in files or "edgeData.dat" in files:
                return root

    # 2. Check for any .ipa or .zip archive in game_data/ or ROOT_DIR
    archives = (
        glob.glob(os.path.join(GAME_DATA_DIR, "*.ipa")) +
        glob.glob(os.path.join(ROOT_DIR, "*.ipa")) +
        glob.glob(os.path.join(GAME_DATA_DIR, "*.zip")) +
        glob.glob(os.path.join(ROOT_DIR, "*.zip"))
    )
    for arc_path in archives:
        try:
            with zipfile.ZipFile(arc_path, "r") as z:
                names = z.namelist()
                has_payload = any("Payload/" in n or "roleConfig.json" in n for n in names)
                if not has_payload:
                    continue
                print(f"[+] Found game archive: {arc_path}")
                extract_tmp = os.path.join(GAME_DATA_DIR, "_extracted_app")
                os.makedirs(extract_tmp, exist_ok=True)
                for item in names:
                    if not item.endswith("/"):
                        z.extract(item, extract_tmp)
                for root, dirs, files in os.walk(extract_tmp):
                    if "roleConfig.json" in files or "edgeData.dat" in files:
                        return root
        except Exception:
            continue

    return None

def decode_pvr_ccz_to_image(ccz_bytes: bytes) -> Image.Image:
    """
    Decompresses a .pvr.ccz file using zlib, parses PVRv2 header,
    and decodes PVRTC 4bpp RGBA to a PIL Image.
    """
    if ccz_bytes[:4] == b"CCZ!" or ccz_bytes[:4] == b"!ZCC":
        pvr_bytes = zlib.decompress(ccz_bytes[16:])
    else:
        pvr_bytes = ccz_bytes

    # Parse PVR v2 header (52 bytes)
    header_len, h, w, mipmaps, flags, data_len, bpp, r_mask, g_mask, b_mask, a_mask, pvr_magic, num_surfs = struct.unpack('<IIIIIIIIIIIII', pvr_bytes[:52])
    pvr_data = pvr_bytes[header_len:header_len + data_len] if data_len > 0 else pvr_bytes[header_len:]
    
    # Decode PVRTC (bpp=4 -> PVRTC4)
    decoded = texture2ddecoder.decode_pvrtc(pvr_data, w, h, False)
    return Image.frombytes("RGBA", (w, h), decoded, "raw", "BGRA")

def extract_plist_atlas(plist_data: bytes, atlas_img: Image.Image, dest_dir: str):
    """
    Extracts all sub-textures from an atlas using TexturePacker plist metadata.
    Restores untrimmed canvas size and handles 90 degree CCW atlas rotation.
    """
    os.makedirs(dest_dir, exist_ok=True)
    pl = plistlib.loads(plist_data)
    frames = pl.get("frames", {})
    count = 0

    for frame_name, info in frames.items():
        frame_name_clean = frame_name.replace("\\", "/")
        out_path = os.path.join(dest_dir, frame_name_clean)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)

        rect_str = info["frame"].replace("{", "").replace("}", "")
        x, y, w, h = [int(v) for v in rect_str.split(",")]

        src_str = info.get("sourceSize", info["frame"]).replace("{", "").replace("}", "")
        sw, sh = [int(v) for v in src_str.split(",")[:2]]

        col_str = info.get("sourceColorRect", None)
        if col_str:
            cx, cy, cw, ch = [int(v) for v in col_str.replace("{", "").replace("}", "").split(",")]
        else:
            cx, cy, cw, ch = 0, 0, w, h

        rot = info.get("rotated", False)

        if rot:
            crop = atlas_img.crop((x, y, x + h, y + w)).transpose(Image.ROTATE_270)
        else:
            crop = atlas_img.crop((x, y, x + w, y + h))

        canvas = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
        canvas.paste(crop, (cx, cy))
        canvas.save(out_path)
        count += 1

    return count

def setup_textures(app_dir: str):
    print("[*] Processing and extracting sprite atlases...")
    atlases = [
        # (name, dest_subfolder)
        ("TextureS1", "suite_1"),
        ("TextureS2", "suite_2"),
        ("TextureS3", "suite_3"),
        ("TextureS4", "suite_4"),
        ("FargroundsS1", "suite_1"),
        ("FargroundsS2", "suite_2"),
        ("FargroundsS3", "suite_3"),
        ("FargroundsS4", "suite_4"),
        ("DynamicObjectsLite", "dynamic"),
        ("CharActions", "character"),
    ]

    for name, subfolder in atlases:
        dest_dir = os.path.join(SPRITES_DIR, subfolder)
        plist_path = os.path.join(app_dir, f"{name}.plist")
        if not os.path.exists(plist_path):
            continue

        with open(plist_path, "rb") as f:
            plist_data = f.read()

        # Check for pre-extracted PNG first, then PVR.CCZ, then PVR
        png_path = os.path.join(app_dir, "extracted", f"{name}.png")
        ccz_path = os.path.join(app_dir, f"{name}.pvr.ccz")
        pvr_path = os.path.join(app_dir, f"{name}.pvr")

        atlas_img = None
        if os.path.exists(png_path):
            atlas_img = Image.open(png_path)
        elif os.path.exists(ccz_path):
            with open(ccz_path, "rb") as f:
                atlas_img = decode_pvr_ccz_to_image(f.read())
        elif os.path.exists(pvr_path):
            with open(pvr_path, "rb") as f:
                atlas_img = decode_pvr_ccz_to_image(f.read())

        if atlas_img:
            count = extract_plist_atlas(plist_data, atlas_img, dest_dir)
            print(f"  [+] {name} -> {count} sprites extracted to {subfolder}/")

def convert_edge_data(app_dir: str):
    print("[*] Converting collision edge data...")
    meta_path = os.path.join(app_dir, "edgeDataMeta.json")
    data_path = os.path.join(app_dir, "edgeData.dat")
    out_json = os.path.join(DATA_DIR, "edge_data.json")

    if not os.path.exists(meta_path) or not os.path.exists(data_path):
        print("  [-] edgeData not found in source directory.")
        return

    with open(meta_path, "r") as f:
        meta = json.load(f)

    edges = {}
    with open(data_path, "rb") as f:
        for edge_id, entry in meta.items():
            f.seek(entry["offset"])
            raw = f.read(entry["count"] * 8)
            pts = []
            for i in range(entry["count"]):
                px, py = struct.unpack("<ff", raw[i * 8 : (i + 1) * 8])
                pts.append([round(px, 3), round(py, 3)])
            edges[edge_id] = pts

    os.makedirs(DATA_DIR, exist_ok=True)
    with open(out_json, "w") as f:
        json.dump(edges, f)
    print(f"  [+] Saved {len(edges)} collision chains to project/data/edge_data.json")

def copy_levels_and_scripts(app_dir: str):
    print("[*] Copying level XML and Lua scripts...")
    os.makedirs(LEVELS_DIR, exist_ok=True)
    level_files = glob.glob(os.path.join(app_dir, "Level_[0-9][0-9][0-9]"))
    for lf in level_files:
        name = os.path.basename(lf)
        shutil.copy(lf, os.path.join(LEVELS_DIR, f"{name}.xml"))

    lua_files = glob.glob(os.path.join(app_dir, "Level_[0-9][0-9][0-9].lua"))
    for lf in lua_files:
        shutil.copy(lf, os.path.join(LEVELS_DIR, os.path.basename(lf)))

    print(f"  [+] Copied {len(level_files)} XML levels and {len(lua_files)} Lua scripts.")

    # Copy config JSONs
    for jf in ["roleConfig.json", "strings.json", "LevelDependency.json", "LevelSelectData.json", "levelScore.json"]:
        src = os.path.join(app_dir, jf)
        if os.path.exists(src):
            shutil.copy(src, os.path.join(DATA_DIR, jf))

def copy_audio_files(app_dir: str):
    print("[*] Copying audio sound effects...")
    os.makedirs(AUDIO_DIR, exist_ok=True)
    wavs = glob.glob(os.path.join(app_dir, "*.wav"))
    for w in wavs:
        shutil.copy(w, os.path.join(AUDIO_DIR, os.path.basename(w)))
    print(f"  [+] Copied {len(wavs)} audio WAV files.")

def main():
    print("==================================================")
    print("   FlyMe2TheMoon - Automated Asset Setup Tool     ")
    print("==================================================")

    os.makedirs(GAME_DATA_DIR, exist_ok=True)
    app_dir = find_source_data()

    if not app_dir:
        print("\n[!] ERROR: No original game data found!")
        print("\nPlease do one of the following:")
        print(f"  1) Drop your 'Fly2theMoon.ipa' file into:\n     {GAME_DATA_DIR}")
        print(f"  2) Or extract your IPA and drop 'Payload/Fly2theMoon.app' into:\n     {GAME_DATA_DIR}")
        print("\nThen run this script again:\n  python tools/setup_game_data.py (or run setup_game_data.bat)")
        sys.exit(1)

    print(f"[+] Using source game data from: {app_dir}")
    setup_textures(app_dir)
    convert_edge_data(app_dir)
    copy_levels_and_scripts(app_dir)
    copy_audio_files(app_dir)

    print("\n==================================================")
    print("   Setup Complete! All assets are ready.          ")
    print("   You can now run FlyMe2TheMoon in Godot!        ")
    print("==================================================")

if __name__ == "__main__":
    main()
