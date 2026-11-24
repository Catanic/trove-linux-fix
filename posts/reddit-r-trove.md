**Title:** [Linux/Steam Deck] Trove broken since XIGNCODE? Here's a working fix (plain Wine instead of Proton)

---

If you're on Steam Deck or Linux and Trove stopped working when XIGNCODE3 was added, with Play in Glyph doing nothing, here's a fix that has my Deck running Trove again, anti-cheat included.

**Full disclosure:** I didn't figure this out myself. The troubleshooting, the setup script and this write-up were done by an AI assistant (Claude) on my Steam Deck, and I tested the result. I'm sharing it because it works and other people are stuck.

**The short version:** the anti-cheat loader quits under *every* Proton version (10 were tested, including Experimental and GE). Under plain **WineHQ Wine** it starts normally and the game runs fine.

**How to use it**

1. Install Trove on Steam as usual (no need to launch it).
2. Get the script: https://github.com/Catanic/trove-linux-fix
3. Close Steam, then run `./install.sh --controller --add-to-steam` in a terminal (Desktop Mode on Deck).
4. Launch **"Trove (Wine)"** from your library and log in with your **Trove email + password**.

**Things to know**

* **No Steam login.** It only works through Proton. Same account, same characters; if you've only ever used Steam login, use "Can't log in?" in Glyph to set a password.
* With `--controller`, press **View (⧉)** in game to switch to controller prompts.
* It's unofficial. The anti-cheat runs normally and isn't modified, but nobody can promise anything about bans. Your call.
* The script also fixes two problems with plain Wine: the Glyph launcher freezing (Wine audio bug, so the launcher is muted, not the game) and white boxes in game (it uses DXVK).
* The script has been tested on one Steam Deck so far. Please read it before running it, as with any script from the internet.

**Why Proton fails, for the curious:** the loader checks `ntoskrnl.exe` against Windows' signature catalog and exits with code 1048 when that fails under Proton. Plain Wine skips that path. Details are posted for Valve on [Proton#2986](https://github.com/ValveSoftware/Proton/issues/2986), so hopefully the regular Steam version works again eventually.

If something doesn't work, comment with your device and what Glyph does.
