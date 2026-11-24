#!/usr/bin/env bash
# trove-linux-fix (written by an AI assistant, Claude; read before running): run Trove on Linux / Steam Deck with plain WineHQ Wine instead of Proton.
#
# Why: Trove's XIGNCODE3 anti-cheat loader (xldr_Trove_GL_loader_x64.exe) exits with
# code 1048 under every Proton build tested (Nov 2026), so pressing Play in Glyph does
# nothing. Under plain WineHQ Wine the anti-cheat starts and the game runs.
#
# What this does (all inside one folder, default ~/Games/Trove-wine):
#   1. Installs the WineHQ Wine flatpak (org.winehq.Wine) if it's missing.
#   2. Copies your Steam install of Trove (Glyph launcher + game files) into the folder.
#   3. Switches Glyph to email/password login (Steam login needs Proton's Steam bridge).
#   4. Creates a Wine prefix with three fixes:
#        - audio drivers disabled for the Glyph launcher only (Wine's audio busy-loops
#          inside Glyph and freezes it; the game itself keeps sound)
#        - DXVK for the game only (Wine's built-in D3D draws white boxes and is slow)
#        - optional controller mode (--controller)
#   5. Writes a launcher script (trove.sh) and optionally adds it to Steam (--add-to-steam).
#
# Your Steam install of Trove is only read, never modified.
#
# Usage: ./install.sh [--dir PATH] [--controller] [--add-to-steam] [--yes]
#        ./install.sh --help

set -euo pipefail

APP=org.winehq.Wine
DEST="${HOME}/Games/Trove-wine"
CONTROLLER=0
ADD_TO_STEAM=0
ASSUME_YES=0
SRC_OVERRIDE=""

say()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33mwarning:\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
  sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'
  cat <<'EOF'
Options:
  --dir PATH       Install folder (default: ~/Games/Trove-wine)
  --source PATH    Trove folder to copy from (the one containing GlyphClient.exe).
                   Default: your Steam install of Trove.
  --controller     Turn on Trove's controller mode + console UI (for Steam Deck / gamepads)
  --add-to-steam   Add a "Trove (Wine)" shortcut to Steam (Steam must be closed)
  --yes            Don't ask for confirmation
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir) DEST="${2:?--dir needs a path}"; shift 2 ;;
    --source) SRC_OVERRIDE="${2:?--source needs a path}"; shift 2 ;;
    --controller) CONTROLLER=1; shift ;;
    --add-to-steam) ADD_TO_STEAM=1; shift ;;
    --yes|-y) ASSUME_YES=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1 (see --help)" ;;
  esac
done
DEST="$(realpath -m "$DEST")"

command -v flatpak >/dev/null || die "flatpak is required (it is preinstalled on SteamOS)."
command -v python3 >/dev/null || die "python3 is required."

# ---------------------------------------------------------------- find Steam + Trove
STEAM_ROOTS=()
for r in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
  [ -d "$r/steamapps" ] && STEAM_ROOTS+=("$(realpath "$r")")
done
[ ${#STEAM_ROOTS[@]} -gt 0 ] || die "couldn't find a Steam install."
mapfile -t STEAM_ROOTS < <(printf '%s\n' "${STEAM_ROOTS[@]}" | awk '!seen[$0]++')
STEAM="${STEAM_ROOTS[0]}"

# all library folders from every libraryfolders.vdf
LIBS=()
for r in "${STEAM_ROOTS[@]}"; do
  LIBS+=("$r")
  vdf="$r/steamapps/libraryfolders.vdf"
  [ -f "$vdf" ] && while IFS= read -r p; do LIBS+=("$p"); done < <(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"/\1/p' "$vdf")
done

SRC=""
if [ -n "$SRC_OVERRIDE" ]; then
  SRC="$(realpath "$SRC_OVERRIDE")"
  [ -f "$SRC/GlyphClient.exe" ] || die "--source: no GlyphClient.exe in $SRC"
fi
[ -z "$SRC" ] && for l in "${LIBS[@]}"; do
  if [ -f "$l/steamapps/common/Trove/GlyphClient.exe" ]; then SRC="$l/steamapps/common/Trove"; break; fi
done
[ -n "$SRC" ] || die "Trove isn't installed through Steam. Install it (it's free), let the download finish, then run this again. You don't need to launch it."
say "Found Trove at: $SRC"

# ---------------------------------------------------------------- confirm
echo
echo "This will set up Trove under plain Wine in: $DEST"
[ "$CONTROLLER" = 1 ] && echo "  + controller mode"
[ "$ADD_TO_STEAM" = 1 ] && echo "  + Steam shortcut \"Trove (Wine)\""
echo "You'll log in to Glyph with your Trove email + password (not Steam)."
if [ "$ASSUME_YES" != 1 ]; then
  read -r -p "Continue? [y/N] " a; [[ "$a" =~ ^[Yy] ]] || exit 1
fi

if flatpak ps --columns=application 2>/dev/null | grep -qx "$APP"; then
  die "Wine (flatpak $APP) is running. Close Trove/Glyph first, or run: flatpak kill $APP"
fi

# ---------------------------------------------------------------- 1. Wine
if ! flatpak info "$APP" >/dev/null 2>&1; then
  say "Installing WineHQ Wine (flatpak $APP)…"
  flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  flatpak install --user -y flathub "$APP"
else
  say "WineHQ Wine flatpak already installed ($(flatpak info "$APP" | sed -n 's/^ *Version: //p'))"
fi

# ---------------------------------------------------------------- 2. copy files
say "Copying Trove files (this can take a minute)…"
mkdir -p "$DEST/Trove"
if command -v rsync >/dev/null; then
  rsync -a --exclude Logs "$SRC/" "$DEST/Trove/"
else
  cp -a "$SRC/." "$DEST/Trove/" && rm -rf "$DEST/Trove/Logs"
fi

# ---------------------------------------------------------------- 3. Glyph: email login
CFG="$DEST/Trove/GlyphClient.cfg"
[ -f "$CFG" ] || die "GlyphClient.cfg missing in $DEST/Trove"
if grep -q '^UseSteam=' "$CFG"; then sed -i 's/^UseSteam=.*/UseSteam=0/' "$CFG"
else sed -i 's/^\[Glyph\]$/[Glyph]\nUseSteam=0/' "$CFG"; fi
say "Glyph set to email/password login"

flatpak override --user --filesystem="$DEST" "$APP"

# ---------------------------------------------------------------- 4. DXVK
DXVK_SRC=""
for r in "${STEAM_ROOTS[@]}"; do
  for p in "$r/steamapps/common/Proton - Experimental" "$r/steamapps/common/Proton Hotfix" \
           "$r"/steamapps/common/Proton\ [0-9]* "$r"/compatibilitytools.d/*; do
    if [ -f "$p/files/lib/wine/dxvk/x86_64-windows/d3d11.dll" ]; then DXVK_SRC="$p/files/lib/wine/dxvk"; break 2; fi
  done
done
if [ -z "$DXVK_SRC" ]; then
  say "No Proton with DXVK found locally; downloading DXVK from GitHub…"
  command -v curl >/dev/null || die "curl is required to download DXVK"
  url=$(curl -fsSL https://api.github.com/repos/doitsujin/dxvk/releases/latest | python3 -c \
    'import json,sys; a=[x["browser_download_url"] for x in json.load(sys.stdin)["assets"] if x["name"].endswith(".tar.gz") and "native" not in x["name"]]; print(a[0])')
  tmp=$(mktemp -d); curl -fsSL "$url" -o "$tmp/dxvk.tar.gz"; tar -xzf "$tmp/dxvk.tar.gz" -C "$tmp"
  d=$(find "$tmp" -maxdepth 1 -type d -name 'dxvk-*' | head -1)
  mkdir -p "$tmp/dxvk"; ln -s "$d/x64" "$tmp/dxvk/x86_64-windows"; ln -s "$d/x32" "$tmp/dxvk/i386-windows"
  DXVK_SRC="$tmp/dxvk"
fi
say "DXVK from: $DXVK_SRC"

# ---------------------------------------------------------------- 5. launcher script
cat > "$DEST/trove.sh" <<'LAUNCHER'
#!/bin/bash
# Launch Trove (Glyph launcher) under plain WineHQ Wine (flatpak org.winehq.Wine).
# Made by trove-linux-fix. Set TROVE_DEBUG=1 to write a Wine trace to last-run.log.
D="$(cd "$(dirname "$0")" && pwd)"
export WINEPREFIX="$D/prefix"
cd "$D/Trove" || exit 1

# Each `flatpak run` gets a private /tmp, so a second launch would start a second
# wineserver on the same prefix and break things. Refuse unless asked to restart.
if flatpak ps --columns=application 2>/dev/null | grep -qx org.winehq.Wine; then
  if [ "${1:-}" = "--restart" ]; then
    flatpak kill org.winehq.Wine; sleep 3; shift
  else
    echo "Trove/Wine is already running. Use: $0 --restart" >&2
    command -v notify-send >/dev/null && notify-send "Trove" "Already running (use trove.sh --restart to force)"
    exit 1
  fi
fi

if [ "${TROVE_DEBUG:-0}" = 1 ]; then
  DBG="+timestamp,+pid,+process,+wintrust,+loaddll"
  exec >"$D/last-run.log" 2>&1
else
  DBG="-all"
fi

exec flatpak run \
  --env=WINEPREFIX="$WINEPREFIX" \
  --env=WINEDEBUG="$DBG" \
  --env=QT_OPENGL=software \
  --command=wine org.winehq.Wine \
  "$D/Trove/GlyphClient.exe" "$@"
LAUNCHER
chmod +x "$DEST/trove.sh"

# ---------------------------------------------------------------- 6. prefix + registry
# One flatpak instance does everything so only one wineserver ever touches the prefix.
say "Creating Wine prefix and applying fixes…"
mkdir -p "$DEST/prefix"
flatpak run --env=WINEPREFIX="$DEST/prefix" --env=WINEDEBUG=-all --command=bash "$APP" -c '
  set -e
  wineboot -i >/dev/null 2>&1 || true
  wineserver -w
  r() { wine reg add "$1" /v "$2" /t REG_SZ /d "$3" /f >/dev/null 2>&1; }
  for exe in GlyphClientApp.exe GlyphClient.exe; do
    r "HKCU\\Software\\Wine\\AppDefaults\\$exe\\DllOverrides" winepulse.drv ""
    r "HKCU\\Software\\Wine\\AppDefaults\\$exe\\DllOverrides" winealsa.drv ""
  done
  for dll in d3d11 dxgi d3d10core d3d9; do
    r "HKCU\\Software\\Wine\\AppDefaults\\trove_x64.exe\\DllOverrides" $dll native
  done
  wineserver -w
'

W="$DEST/prefix/drive_c/windows"
[ -d "$W/system32" ] || die "Wine prefix creation failed ($W missing)"
mkdir -p "$DEST/dxvk-backup/system32" "$DEST/dxvk-backup/syswow64"
for pair in x86_64-windows:system32 i386-windows:syswow64; do
  s="$DXVK_SRC/${pair%%:*}"; t="$W/${pair##*:}"
  [ -d "$t" ] || continue
  for f in d3d11 dxgi d3d10core d3d9; do
    [ -f "$s/$f.dll" ] || continue
    [ -f "$DEST/dxvk-backup/${pair##*:}/$f.dll" ] || cp -f "$t/$f.dll" "$DEST/dxvk-backup/${pair##*:}/" 2>/dev/null || true
    cp -f "$s/$f.dll" "$t/.$f.dll.new" && mv -f "$t/.$f.dll.new" "$t/$f.dll"
  done
done
say "DXVK installed for trove_x64.exe only (originals in dxvk-backup/)"

# ---------------------------------------------------------------- 7. controller mode
if [ "$CONTROLLER" = 1 ]; then
  WUSER=$(ls "$DEST/prefix/drive_c/users" | grep -vx Public | head -1)
  TC="$DEST/prefix/drive_c/users/$WUSER/AppData/Roaming/Trove/Trove.cfg"
  mkdir -p "$(dirname "$TC")"
  python3 - "$TC" <<'PY'
import sys, os, re
path = sys.argv[1]
want = {"Input": {"ControllerEnabled": "1"}, "UI": {"ForceConsoleUI": "1"}}
text = open(path).read() if os.path.exists(path) else ""
for sec, kv in want.items():
    for k, v in kv.items():
        if re.search(rf"^{k} = .*$", text, re.M):
            text = re.sub(rf"^{k} = .*$", f"{k} = {v}", text, flags=re.M)
        elif re.search(rf"^\[{sec}\]$", text, re.M):
            text = re.sub(rf"^\[{sec}\]$", f"[{sec}]\n{k} = {v}", text, count=1, flags=re.M)
        else:
            text += f"\n[{sec}]\n{k} = {v}\n"
open(path, "w").write(text)
PY
  say "Controller mode on (press View/Back in game to switch HUD to controller prompts)"
fi

# ---------------------------------------------------------------- 8. Steam shortcut
if [ "$ADD_TO_STEAM" = 1 ]; then
  if pgrep -x steam >/dev/null || pgrep -f 'steamrt64/steam ' >/dev/null || pgrep -f 'ubuntu12_32/steam' >/dev/null; then
    warn "Steam is running, so the shortcut was NOT added (Steam overwrites the file on exit)."
    warn "Close Steam and run: $0 --dir \"$DEST\" --add-to-steam --yes   (or add trove.sh as a Non-Steam Game by hand)"
  else
    python3 - "$STEAM" "$DEST" <<'PY'
import os, sys, glob, shutil, struct, zlib
steam, dest = sys.argv[1], sys.argv[2]
def read(d, i=0):
    o = {}
    while True:
        t = d[i]; i += 1
        if t == 8: return o, i
        j = d.index(b"\0", i); k = d[i:j].decode("utf-8", "replace"); i = j + 1
        if t == 0: o[k], i = read(d, i)
        elif t == 1: j = d.index(b"\0", i); o[k] = d[i:j].decode("utf-8", "replace"); i = j + 1
        elif t == 2: o[k] = struct.unpack("<i", d[i:i+4])[0]; i += 4
        else: raise ValueError(f"unknown vdf type {t}")
def write(d):
    b = bytearray()
    for k, v in d.items():
        kb = k.encode() + b"\0"
        if isinstance(v, dict): b += b"\0" + kb + write(v)
        elif isinstance(v, int): b += b"\2" + kb + struct.pack("<i", v)
        else: b += b"\1" + kb + str(v).encode() + b"\0"
    return bytes(b + b"\x08")
name, exe = "Trove (Wine)", f'"{dest}/trove.sh"'
appid = (zlib.crc32((exe + name).encode()) & 0xFFFFFFFF) | 0x80000000
lib = os.path.join(steam, "appcache/librarycache/304050")
def art(pattern):
    m = glob.glob(os.path.join(lib, "**", pattern), recursive=True)
    return m[0] if m else None
users = [u for u in glob.glob(os.path.join(steam, "userdata/*")) if os.path.basename(u).isdigit() and os.path.basename(u) != "0"]
for u in users:
    cfgdir = os.path.join(u, "config"); os.makedirs(cfgdir, exist_ok=True)
    sc = os.path.join(cfgdir, "shortcuts.vdf")
    root = read(open(sc, "rb").read())[0] if os.path.exists(sc) else {"shortcuts": {}}
    shortcuts = root.setdefault("shortcuts", {})
    if any(v.get("AppName") == name for v in shortcuts.values()):
        print(f"  shortcut already present for Steam user {os.path.basename(u)}"); continue
    if os.path.exists(sc): shutil.copy2(sc, sc + ".bak-trove")
    icons = [p for p in glob.glob(os.path.join(lib, "*.jpg"))]  # top-level jpg = app icon
    icon = ""
    if icons:
        icon = os.path.join(dest, "trove-icon.jpg"); shutil.copy2(icons[0], icon)
    shortcuts[str(max([int(k) for k in shortcuts] + [-1]) + 1)] = {
        "appid": struct.unpack("<i", struct.pack("<I", appid))[0], "AppName": name, "Exe": exe,
        "StartDir": f'"{dest}/"', "icon": icon, "ShortcutPath": "", "LaunchOptions": "",
        "IsHidden": 0, "AllowDesktopConfig": 1, "AllowOverlay": 1, "OpenVR": 0, "Devkit": 0,
        "DevkitGameID": "", "DevkitOverrideAppID": 0, "LastPlayTime": 0, "FlatpakAppID": "", "tags": {}}
    open(sc, "wb").write(write(root)); read(open(sc, "rb").read())
    grid = os.path.join(cfgdir, "grid"); os.makedirs(grid, exist_ok=True)
    for src, dst in [("library_capsule.jpg", f"{appid}p.jpg"), ("library_header.jpg", f"{appid}.jpg"),
                     ("library_hero.jpg", f"{appid}_hero.jpg"), ("logo.png", f"{appid}_logo.png")]:
        a = art(src)
        if a: shutil.copy2(a, os.path.join(grid, dst))
    print(f"  added \"{name}\" for Steam user {os.path.basename(u)}")
PY
    say "Steam shortcut added. Start Steam and look for \"Trove (Wine)\" in your library."
  fi
fi

# ---------------------------------------------------------------- done
cat <<EOF

$(say "Done!")
Launch:   $DEST/trove.sh   (or the "Trove (Wine)" Steam shortcut / add trove.sh as a Non-Steam Game)
Login:    your Trove email + password. Never set one? Use "Can't log in?" in Glyph to set it.
Stuck:    $DEST/trove.sh --restart
Uninstall: flatpak kill $APP; rm -rf "$DEST"   (and remove the Steam shortcut)

Glyph patches the game itself; you don't need to update Trove through Steam.
EOF
