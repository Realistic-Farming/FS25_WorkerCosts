#!/usr/bin/env bash
# build.sh — Build and optionally deploy FS25_WorkerCosts
#
# Usage:
#   bash build.sh           # build zip only
#   bash build.sh --deploy  # build zip and copy to active mods folder
#
# NOTE: Uses PowerShell + .NET ZipArchive (NOT Compress-Archive) to guarantee
# forward-slash entry paths inside the zip.  Compress-Archive produces backslash
# paths which FS25 silently rejects on load.

set -euo pipefail

MOD_NAME="FS25_WorkerCosts"
ZIP_NAME="${MOD_NAME}.zip"
DEPLOY_DIR="/c/Users/tison/Documents/My Games/FarmingSimulator2025/mods"

# Pull version from modDesc.xml for the build banner
VERSION=$(grep -oP '(?<=<version>)[^<]+' modDesc.xml)

echo "Building ${MOD_NAME} v${VERSION}..."

# Files and directories to include in the zip (relative to repo root)
INCLUDE=("modDesc.xml" "icon.dds" "tab_icons.dds" "WorkerCostsSlice.dds" "README.md" "src" "textures" "xml")

# Absolute path of the repo root (convert to Windows path for PowerShell)
REPO_ROOT=$(pwd -W)
ZIP_ABS="${REPO_ROOT}\\${ZIP_NAME}"

# Build the include list as a PowerShell array literal
PS_INCLUDE="@("
for item in "${INCLUDE[@]}"; do
    PS_INCLUDE+="'${item}',"
done
PS_INCLUDE="${PS_INCLUDE%,})"  # strip trailing comma

# Use .NET ZipArchive directly so we can force forward-slash entry names.
# Compress-Archive is intentionally avoided — it uses backslash separators.
powershell.exe -NoProfile -Command "
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    \$repoRoot  = '${REPO_ROOT}'
    \$zipPath   = '${ZIP_ABS}'
    \$include   = ${PS_INCLUDE}

    if (Test-Path \$zipPath) { Remove-Item \$zipPath }

    \$zip = [System.IO.Compression.ZipFile]::Open(\$zipPath, 'Create')
    try {
        foreach (\$entry in \$include) {
            \$fullEntry = Join-Path \$repoRoot \$entry
            if (Test-Path \$fullEntry -PathType Leaf) {
                # Single file
                \$entryName = \$entry.Replace('\\', '/')
                [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                    \$zip, \$fullEntry, \$entryName, 'Optimal') | Out-Null
            } elseif (Test-Path \$fullEntry -PathType Container) {
                # Directory — recurse and add each file with a relative path
                Get-ChildItem -Recurse -File \$fullEntry | ForEach-Object {
                    \$rel = \$_.FullName.Substring(\$repoRoot.Length + 1).Replace('\\', '/')
                    [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
                        \$zip, \$_.FullName, \$rel, 'Optimal') | Out-Null
                }
            }
        }
    } finally {
        \$zip.Dispose()
    }
    Write-Host 'Zip created successfully'
"

SIZE=$(du -sh "$ZIP_NAME" | cut -f1)
echo "Built: ${ZIP_NAME} (${SIZE})"

# Deploy
if [[ "${1:-}" == "--deploy" ]]; then
    DEPLOY_WIN="/c/Users/tison/Documents/My Games/FarmingSimulator2025/mods"
    if [[ ! -d "$DEPLOY_WIN" ]]; then
        echo "ERROR: Deploy directory not found: $DEPLOY_WIN" >&2
        exit 1
    fi
    cp "$ZIP_NAME" "$DEPLOY_WIN/$ZIP_NAME"
    echo "Deployed to: $DEPLOY_WIN/$ZIP_NAME"
    echo "Check log:   /c/Users/tison/Documents/My Games/FarmingSimulator2025/log.txt"
fi

echo "Done."
