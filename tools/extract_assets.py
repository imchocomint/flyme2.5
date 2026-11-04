import os
import glob
import json
import struct
import shutil
import plistlib
from PIL import Image

BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
APP_DIR = os.path.join(BASE_DIR, "source", "Payload", "Fly2theMoon.app")
EXTRACTED_DIR = os.path.join(APP_DIR, "extracted")
PROJECT_DIR = os.path.join(BASE_DIR, "project")
SPRITES_DIR = os.path.join(PROJECT_DIR, "assets", "sprites")
AUDIO_DIR = os.path.join(PROJECT_DIR, "assets", "audio")
DATA_DIR = os.path.join(PROJECT_DIR, "data")
LEVELS_DIR = os.path.join(DATA_DIR, "levels")

def extract_plist_atlas(plist_path, atlas_png_path, dest_dir):
    """
    Extracts all frames from a TexturePacker plist + atlas PNG.
    Restores untrimmed canvas size and handles 90 deg CCW atlas rotation.
    """
    os.makedirs(dest_dir, exist_ok=True)
    with open(plist_path, "rb") as f:
        pl = plistlib.load(f)
    
    atlas = Image.open(atlas_png_path)
    frames = pl.get("frames", {})
    count = 0
    
    for frame_name, info in frames.items():
        # Clean relative frame path
        frame_name_clean = frame_name.replace("\\", "/")
        out_path = os.path.join(dest_dir, frame_name_clean)
        os.makedirs(os.path.dirname(out_path), exist_ok=True)
        
        # Parse coordinates
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
            crop = atlas.crop((x, y, x + h, y + w)).transpose(Image.ROTATE_270)
        else:
            crop = atlas.crop((x, y, x + w, y + h))
        
        canvas = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
        canvas.paste(crop, (cx, cy))
        canvas.save(out_path)
        count += 1
        
    print(f"Extracted {count} frames from {os.path.basename(plist_path)} -> {os.path.basename(dest_dir)}")

def extract_all_sprites():
    print("=== Extracting Sprites ===")
    
    # 1. Suites 1 through 4 (TextureS and FargroundsS)
    for s in range(1, 5):
        suite_dir = os.path.join(SPRITES_DIR, f"suite_{s}")
        
        tex_plist = os.path.join(APP_DIR, f"TextureS{s}.plist")
        tex_png = os.path.join(EXTRACTED_DIR, f"TextureS{s}.png")
        if os.path.exists(tex_plist) and os.path.exists(tex_png):
            extract_plist_atlas(tex_plist, tex_png, suite_dir)
            
        fg_plist = os.path.join(APP_DIR, f"FargroundsS{s}.plist")
        fg_png = os.path.join(EXTRACTED_DIR, f"FargroundsS{s}.png")
        if os.path.exists(fg_plist) and os.path.exists(fg_png):
            extract_plist_atlas(fg_plist, fg_png, suite_dir)
            
    # 2. DynamicObjectsLite
    dyn_plist = os.path.join(APP_DIR, "DynamicObjectsLite.plist")
    dyn_png = os.path.join(EXTRACTED_DIR, "DynamicObjectsLite.png")
    if os.path.exists(dyn_plist) and os.path.exists(dyn_png):
        extract_plist_atlas(dyn_plist, dyn_png, os.path.join(SPRITES_DIR, "dynamic"))

    # 3. CharActions
    char_plist = os.path.join(APP_DIR, "CharActions.plist")
    char_png = os.path.join(EXTRACTED_DIR, "CharActions.png")
    if os.path.exists(char_plist) and os.path.exists(char_png):
        extract_plist_atlas(char_plist, char_png, os.path.join(SPRITES_DIR, "character"))

def convert_edge_data():
    print("=== Converting Collision Edge Data ===")
    os.makedirs(DATA_DIR, exist_ok=True)
    meta_path = os.path.join(APP_DIR, "edgeDataMeta.json")
    data_path = os.path.join(APP_DIR, "edgeData.dat")
    out_json_path = os.path.join(DATA_DIR, "edge_data.json")
    
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
            
    with open(out_json_path, "w") as f:
        json.dump(edges, f)
    print(f"Exported {len(edges)} collision chains to {out_json_path}")

def copy_levels_and_metadata():
    print("=== Copying Levels and Game Data ===")
    os.makedirs(LEVELS_DIR, exist_ok=True)
    
    # Levels (Level_001 to Level_060)
    level_files = glob.glob(os.path.join(APP_DIR, "Level_[0-9][0-9][0-9]"))
    for lf in level_files:
        name = os.path.basename(lf)
        shutil.copy(lf, os.path.join(LEVELS_DIR, f"{name}.xml"))
    print(f"Copied {len(level_files)} level XML files")
    
    # Lua scripts (Level_001.lua to Level_060.lua)
    lua_files = glob.glob(os.path.join(APP_DIR, "Level_[0-9][0-9][0-9].lua"))
    for lf in lua_files:
        name = os.path.basename(lf)
        shutil.copy(lf, os.path.join(LEVELS_DIR, name))
    print(f"Copied {len(lua_files)} level Lua files")
    
    # JSON metadata files
    for jf in ["roleConfig.json", "strings.json", "LevelDependency.json", "LevelSelectData.json", "levelScore.json"]:
        src = os.path.join(APP_DIR, jf)
        if os.path.exists(src):
            shutil.copy(src, os.path.join(DATA_DIR, jf))
            print(f"Copied {jf}")

def copy_audio():
    print("=== Copying Audio Files ===")
    os.makedirs(AUDIO_DIR, exist_ok=True)
    wavs = glob.glob(os.path.join(APP_DIR, "*.wav"))
    for w in wavs:
        shutil.copy(w, os.path.join(AUDIO_DIR, os.path.basename(w)))
    print(f"Copied {len(wavs)} WAV sound files")

if __name__ == "__main__":
    extract_all_sprites()
    convert_edge_data()
    copy_levels_and_metadata()
    copy_audio()
    print("=== Done! All assets prepared for Godot ===")
