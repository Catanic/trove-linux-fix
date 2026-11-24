# Trove on Linux / Steam Deck (anti-cheat workaround)

Since Trove added the **XIGNCODE3** anti-cheat, it doesn't start under Proton. You press **Play** in Glyph, nothing happens, and Glyph comes back. This repo runs Trove with **plain WineHQ Wine** instead of Proton. The anti-cheat starts normally there and the game runs.

Tested November 2026 on one Steam Deck (SteamOS) with Trove build `STABLE-103-467-A-340101`.

> **How this was made:** the diagnosis, this script and this guide were produced by an AI assistant (Claude) troubleshooting on a Steam Deck, and tested by the Deck's owner. Read the script before you run it.

> **Unofficial.** This isn't supported by gamigo or Valve. As far as we know it doesn't bypass or modify the anti-cheat: XIGNCODE runs normally, just under a different Wine. We can't promise you won't be flagged. Running any anti-cheat game on Linux carries some risk. Use it at your own discretion.

Prefer to do it by hand? See **[MANUAL.md](MANUAL.md)** for the same fix step by step.

## Quick start

1. Install **Trove** through Steam (it's free) and let the download finish. You don't need to launch it.
2. Download this repo and run:

   ```bash
   ./install.sh --controller --add-to-steam
   ```

   - `--controller` turns on Trove's controller mode. Recommended on Steam Deck.
   - `--add-to-steam` adds a **"Trove (Wine)"** shortcut with Trove's artwork. **Close Steam first**, or the script skips this step. You can also add `~/Games/Trove-wine/trove.sh` by hand with *Add a Non-Steam Game*.
3. Start **Trove (Wine)** from Steam, in Gaming Mode or Desktop Mode.
4. Log in to Glyph with your **Trove email and password**. Steam login can't work here (see below). If you've only ever used Steam login, click **"Can't log in?"** to set a password for your account.
5. Press **Play**.

On Steam Deck with `--controller`, press the **View (⧉)** button in game to switch the HUD to controller prompts.

## What the script does

Everything goes in one folder, `~/Games/Trove-wine` by default (change it with `--dir`). Your Steam install is only read, never modified.

| Step | Why |
|---|---|
| Installs the `org.winehq.Wine` flatpak (Wine 11.0) if missing | Plain Wine is what makes the anti-cheat work |
| Copies Trove (Glyph and game files) out of Steam | Glyph patches the game itself, so no Steam updates are needed |
| Sets `UseSteam=0` in `GlyphClient.cfg` | Steam login in Glyph only works through Proton's Steam bridge |
| Disables Wine audio **for the Glyph launcher only** | Wine's audio busy-loops inside Glyph and freezes it: blank window, login never appears. The game keeps its sound. |
| Installs **DXVK** **for `trove_x64.exe` only** | Wine's built-in Direct3D draws white boxes over the HUD and is slow |
| Sets `ControllerEnabled = 1` and `ForceConsoleUI = 1` (with `--controller`) | Trove's console-style HUD with gamepad prompts |
| Writes `trove.sh` | Launcher that refuses to start a second copy (see Troubleshooting) |

DXVK is taken from a Proton install on your system if there is one, otherwise from DXVK's GitHub releases.

## Why Proton doesn't work

Glyph starts the XIGNCODE loader `xldr_Trove_GL_loader_x64.exe`. Under every Proton build we tried, it does the following:

1. probes for known cheat-tool devices (`\Device\WinD`, `\Device\KsDumper`, …)
2. opens `C:\windows\system32\ntoskrnl.exe` and looks its hash up with `CryptCATAdminEnumCatalogFromHash`. Wine has no Microsoft signature catalogs, so the lookup fails.
3. exits with **code 1048**, before the game starts.

Plain Wine 11.0 opens the same files but never makes the catalog lookup. The loader goes on to start `trove_x64.exe` and XIGNCODE's core module.

Builds tested, all exit with 1048: Proton Hotfix (20261110), Proton Experimental (11.0-20261112), Proton 11.0-2e, Proton 10.0-4b, GE-Proton11-12, GE-Proton11-7, GDK-Proton11-7, GE-Proton10-34, dwproton-10.0-16, UMU-Proton-10.0-4. Turning DXVK off (`PROTON_USE_WINED3D=1`) or replacing the prefix's symlinked system DLLs with real copies didn't help either.

The Proton bug report is [ValveSoftware/Proton#2986](https://github.com/ValveSoftware/Proton/issues/2986). Once that's fixed you can go back to the normal Steam version.

> Red herring: Glyph's log says `Failed to set executable permission on ...xldr_Trove_GL_loader_win32.exe`. That's harmless. Glyph starts the x64 loader anyway.

## Troubleshooting

- **Glyph is stuck or won't open:** run `~/Games/Trove-wine/trove.sh --restart`. Each `flatpak run` has its own `/tmp`, so a second copy of Wine would fight the first over the same prefix. The launcher refuses to start a second copy unless you ask it to restart.
- **Stuck on "Authenticating…":** restart as above. Don't edit `NotificationServerUrl` in `GlyphClient.xml`; login depends on it.
- **Debug log:** `TROVE_DEBUG=1 ~/Games/Trove-wine/trove.sh` writes a Wine trace to `~/Games/Trove-wine/last-run.log`. Glyph's own logs are in `~/Games/Trove-wine/Trove/Logs/`.
- **Chat on controller:** Trove has no gamepad button for chat. Open it with Enter or by clicking the chat box with the trackpad, then use **Steam + X** for the on-screen keyboard. You can map Enter to a back button in Steam's controller settings for the shortcut.

## Uninstall

```bash
flatpak kill org.winehq.Wine
rm -rf ~/Games/Trove-wine
```

Then remove the "Trove (Wine)" shortcut in Steam. You can remove the Wine flatpak with `flatpak uninstall org.winehq.Wine` if nothing else uses it.

## Options

```
./install.sh [--dir PATH] [--source PATH] [--controller] [--add-to-steam] [--yes]
  --dir PATH       install folder (default ~/Games/Trove-wine)
  --source PATH    Trove folder to copy from (default: your Steam install of Trove)
  --controller     controller mode + console UI
  --add-to-steam   add a "Trove (Wine)" Steam shortcut (Steam must be closed)
  --yes            don't ask for confirmation
```
