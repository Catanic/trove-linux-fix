# Manual fix: Trove on Linux / Steam Deck with plain Wine

These are the same steps `install.sh` performs, written out so you can do them by hand and see exactly what changes. Allow about 15 minutes.

> Made by an AI assistant (Claude) troubleshooting on a Steam Deck, and tested there. Unofficial; see the anti-cheat note in [README.md](README.md).

**On Steam Deck,** do everything in **Desktop Mode** (Steam button → Power → Switch to Desktop) using the **Konsole** terminal. Commands go in Konsole: copy each one, then paste with `Ctrl+Shift+V`.

Throughout this guide the install folder is `~/Games/Trove-wine`. You can use another one, but change it in every command.

---

## Step 1: Install Trove through Steam

Install Trove from Steam as usual (it's free) and wait for the download to finish. You don't need to launch it. We only copy its files.

Check that it's there:

```bash
ls ~/.local/share/Steam/steamapps/common/Trove/GlyphClient.exe
```

If you get "No such file", Trove is in another Steam library (for example an SD card). Find it with:

```bash
find ~ /run/media -name GlyphClient.exe -path '*Trove*' 2>/dev/null
```

Then use that folder (without `/GlyphClient.exe`) wherever this guide says `~/.local/share/Steam/steamapps/common/Trove`.

## Step 2: Install WineHQ Wine

Either open **Discover**, search for **Wine**, and install the one from **WineHQ** (`org.winehq.Wine`), or run:

```bash
flatpak install --user -y flathub org.winehq.Wine
```

This guide was tested with Wine **11.0**.

## Step 3: Copy Trove to its own folder

```bash
mkdir -p ~/Games/Trove-wine
cp -a ~/.local/share/Steam/steamapps/common/Trove ~/Games/Trove-wine/Trove
rm -rf ~/Games/Trove-wine/Trove/Logs
```

Then give Wine access to that folder (flatpak apps are sandboxed):

```bash
flatpak override --user --filesystem=$HOME/Games/Trove-wine org.winehq.Wine
```

## Step 4: Switch Glyph to email login

Steam login in Glyph only works under Proton, so switch Glyph to email and password:

```bash
sed -i 's/^UseSteam=.*/UseSteam=0/' ~/Games/Trove-wine/Trove/GlyphClient.cfg
grep UseSteam ~/Games/Trove-wine/Trove/GlyphClient.cfg
```

It should print `UseSteam=0`.

> If you've only ever logged in through Steam, you'll set a password in step 9 using **"Can't log in?"** in Glyph. It's the same account and the same characters.

## Step 5: Create the Wine prefix and apply the fixes

This creates a fresh Wine prefix in `~/Games/Trove-wine/prefix` and sets two per-program fixes:

- **No audio for the Glyph launcher only.** Wine's audio gets stuck in a busy loop inside Glyph. The launcher freezes, shows only a blank purple window, and the login never appears. The game itself keeps its sound; turning audio off for the game makes it crash.
- **DXVK for the game only.** Wine's built-in Direct3D draws white boxes over the HUD and is slow. The game DLLs come from DXVK in step 6.

Run this all at once. It's one command; paste the whole block:

```bash
flatpak run --env=WINEPREFIX=$HOME/Games/Trove-wine/prefix --env=WINEDEBUG=-all --command=bash org.winehq.Wine -c '
  wineboot -i; wineserver -w
  for exe in GlyphClientApp.exe GlyphClient.exe; do
    for drv in winepulse.drv winealsa.drv; do
      wine reg add "HKCU\\Software\\Wine\\AppDefaults\\$exe\\DllOverrides" /v $drv /t REG_SZ /d "" /f
    done
  done
  for dll in d3d11 dxgi d3d10core d3d9; do
    wine reg add "HKCU\\Software\\Wine\\AppDefaults\\trove_x64.exe\\DllOverrides" /v $dll /t REG_SZ /d native /f
  done
  wineserver -w'
```

You should see `The operation completed successfully` eight times. If a "Wine Mono" or "Gecko" installer window pops up, you can cancel it; Trove doesn't need them.

> **Important:** never run two Wine commands for this prefix at the same time, and never start Trove twice. Each `flatpak run` has its own private `/tmp`, so two copies of Wine would fight over the same prefix. If anything gets stuck, run `flatpak kill org.winehq.Wine`.

## Step 6: Install DXVK

If you have **Proton Experimental** installed in Steam, copy DXVK from there:

```bash
P="$HOME/.local/share/Steam/steamapps/common/Proton - Experimental/files/lib/wine/dxvk"
W=~/Games/Trove-wine/prefix/drive_c/windows
for f in d3d11 dxgi d3d10core d3d9; do
  cp -f "$P/x86_64-windows/$f.dll" "$W/system32/$f.dll"
  cp -f "$P/i386-windows/$f.dll"   "$W/syswow64/$f.dll"
done
```

No Proton Experimental? Any other Proton or GE-Proton has the same `files/lib/wine/dxvk` folder; change the path in `P=`. Or download a release from <https://github.com/doitsujin/dxvk/releases>, unpack it, and copy `x64/*.dll` to `system32` and `x32/*.dll` to `syswow64`.

## Step 7: Create the launcher script

```bash
cat > ~/Games/Trove-wine/trove.sh <<'EOF'
#!/bin/bash
D="$(cd "$(dirname "$0")" && pwd)"
export WINEPREFIX="$D/prefix"
cd "$D/Trove" || exit 1
if flatpak ps --columns=application 2>/dev/null | grep -qx org.winehq.Wine; then
  if [ "${1:-}" = "--restart" ]; then flatpak kill org.winehq.Wine; sleep 3; shift
  else echo "Already running. Use: $0 --restart" >&2; exit 1; fi
fi
exec flatpak run --env=WINEPREFIX="$WINEPREFIX" --env=WINEDEBUG=-all \
  --env=QT_OPENGL=software --command=wine org.winehq.Wine "$D/Trove/GlyphClient.exe" "$@"
EOF
chmod +x ~/Games/Trove-wine/trove.sh
```

## Step 8: Add it to Steam (optional, recommended on Deck)

In Steam (Desktop Mode): **Games → Add a Non-Steam Game to My Library… → Browse…** Go to `/home/deck/Games/Trove-wine/` (on other systems, your home folder) and pick `trove.sh`. Set the file type filter to "All Files" if it isn't listed. Click **Add Selected Programs**, and rename the entry to "Trove (Wine)" under its Properties if you like.

Launching from Steam also gives you Steam's controller handling in game.

## Step 9: First launch and login

Start **Trove (Wine)** from Steam, or run `~/Games/Trove-wine/trove.sh`.

1. Glyph opens. Click **LOGIN** (top right) and sign in with your **Trove email and password**. Use **"Can't log in?"** if you need to set or reset a password.
2. Glyph checks the files and may download updates.
3. Press **Play**. The XIGNCODE splash appears, then the game.

## Step 10: Controller mode (optional)

Run the game once (step 9) so Trove creates its settings file, then quit Trove. Edit:

```
~/Games/Trove-wine/prefix/drive_c/users/<your user name>/AppData/Roaming/Trove/Trove.cfg
```

Set these two lines (they already exist, with empty values):

```
ControllerEnabled = 1
ForceConsoleUI = 1
```

In game, press **View (⧉)** on the Deck (Back/Select on other controllers) to switch the HUD to controller prompts. Trove has no gamepad button for chat. Click the chat box with the right trackpad (or press Enter), then use **Steam + X** for the on-screen keyboard.

---

## Troubleshooting

| Problem | Fix |
|---|---|
| Glyph shows only a blank purple window and doesn't react | Step 5's audio fix is missing or wasn't applied. Check `grep -A3 'GlyphClientApp.exe' ~/Games/Trove-wine/prefix/user.reg`. |
| "Already running" or Glyph frozen | `~/Games/Trove-wine/trove.sh --restart` |
| Stuck on "Authenticating…" | Restart as above. Don't edit `NotificationServerUrl` in `GlyphClient.xml`; login depends on it. |
| Play does nothing | Check that you launch `trove.sh` and not the original Steam Trove, which still runs on Proton. |
| Game crashes about 15 s after starting | Wine audio may be disabled globally. Make sure `WINEDLLOVERRIDES` isn't set and that only the Glyph entries from step 5 disable audio. |
| White boxes in the HUD, low FPS | DXVK isn't active. Redo step 6 and check the `trove_x64.exe` entries from step 5. |

Glyph's logs: `~/Games/Trove-wine/Trove/Logs/`. For a Wine debug log, launch with:

```bash
cd ~/Games/Trove-wine/Trove && flatpak run --env=WINEPREFIX=$HOME/Games/Trove-wine/prefix \
  --env=WINEDEBUG=+timestamp,+pid,+process,+loaddll --command=wine org.winehq.Wine GlyphClient.exe 2> ~/trove-wine.log
```

## Uninstall

```bash
flatpak kill org.winehq.Wine
rm -rf ~/Games/Trove-wine
```

Remove the Steam shortcut if you added one. To remove Wine too: `flatpak uninstall org.winehq.Wine`.
