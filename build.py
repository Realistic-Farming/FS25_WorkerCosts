import zipfile
import sys
import shutil
import re
from pathlib import Path

# ============================================================
# build.py - Build & deploy FS25_WorkerCosts
# Usage:
#   py build.py            - builds zip only
#   py build.py --deploy   - builds zip AND copies to mods folder
#
# Packaging mirrors the legacy build.sh exactly: an explicit include
# list, written with forward-slash entry paths (FS25 silently rejects
# zips with backslash separators on load).
# ============================================================

MOD_NAME = "FS25_WorkerCosts"
MOD_DIR = Path(__file__).parent.resolve()
ZIP_PATH = MOD_DIR / f"{MOD_NAME}.zip"

# Windows default mods path
MODS_DIR = Path.home() / "Documents" / "My Games" / "FarmingSimulator2025" / "mods"

# Files / directories shipped in the mod (relative to repo root).
INCLUDE = [
    "modDesc.xml",
    "icon.dds",
    "tab_icons.dds",
    "WorkerCostsSlice.dds",
    "README.md",
    "src",
    "xml",
]


def read_version():
    try:
        text = (MOD_DIR / "modDesc.xml").read_text(encoding="utf-8")
        m = re.search(r"<version>([^<]+)</version>", text)
        return m.group(1) if m else "?"
    except OSError:
        return "?"


def add_path(zf, rel):
    full = MOD_DIR / rel
    if full.is_file():
        zf.write(full, Path(rel).as_posix())
        print(f"  + {Path(rel).as_posix()}")
    elif full.is_dir():
        for p in sorted(full.rglob("*")):
            if p.is_file():
                arc = p.relative_to(MOD_DIR).as_posix()
                zf.write(p, arc)
                print(f"  + {arc}")
    else:
        print(f"  ! skipped (missing): {rel}")


def build_zip():
    print("============================================")
    print(f"  Building {MOD_NAME} v{read_version()}")
    print("============================================")

    if ZIP_PATH.exists():
        ZIP_PATH.unlink()
        print("  Removed old zip")

    with zipfile.ZipFile(ZIP_PATH, "w", zipfile.ZIP_DEFLATED) as zf:
        for rel in INCLUDE:
            add_path(zf, rel)

    size_kb = ZIP_PATH.stat().st_size / 1024
    print(f"\n  ZIP created: {ZIP_PATH} ({size_kb:.0f} KB)")


def deploy():
    print("\n  Deploying to mods folder...")
    if not MODS_DIR.exists():
        print(f"  WARNING: Mods folder not found at: {MODS_DIR}")
        sys.exit(1)

    dest = MODS_DIR / f"{MOD_NAME}.zip"
    if dest.exists():
        dest.unlink()
    shutil.copy2(ZIP_PATH, dest)
    print(f"  Deployed: {dest}")


if __name__ == "__main__":
    build_zip()
    if "--deploy" in sys.argv:
        deploy()
    print("\n  Done. Check log.txt for [Worker Costs] entries after launching.")
    print("============================================")
