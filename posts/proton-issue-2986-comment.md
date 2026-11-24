<!-- Post as a comment on https://github.com/ValveSoftware/Proton/issues/2986 -->

Live Trove (now with XIGNCODE3) no longer gets past the anti-cheat loader on any Proton build tested below. It does work under upstream WineHQ 11.0.

> Disclosure: this investigation (the tests, traces and analysis below) was done by an AI assistant (Claude Code) on my Steam Deck. I've checked that the workaround runs the game, and I can run test builds or other debug channels on request.

**System:** Steam Deck OLED, SteamOS 3.9.6 (20261112.101), kernel 7.2.7-valve2, Mesa 26.2.0-devel (RADV VANGOGH)
**Full system information:** GIST_URL
**Trove build:** `STABLE-103-467-A-340101` (live, not PTS)
**Log:** attached `steam-304050.log`, Proton Experimental `experimental-11.0-20261112`, `PROTON_LOG=+wintrust,+crypt,+process`, from the minimal repro below. The loader is pid `014c` in this log; see its `CryptCATAdminEnumCatalogFromHash` lines followed by `NtTerminateProcess ... exit_code 1048`.

**Symptom:** Press Play in Glyph and nothing happens. Glyph starts `xldr_Trove_GL_loader_x64.exe trove_x64.exe -k ... -C [AuthServer] ...`. The loader exits about 3 s later with exit code **1048**. It never installs its service or starts `trove_x64.exe`, and no `xigncode.log` is written.

**Minimal repro (no login needed):** running the loader with only the target argument shows the same behaviour:

```
cd .../steamapps/common/Trove/Games/Trove/Live
STEAM_COMPAT_DATA_PATH=/tmp/pfx STEAM_COMPAT_CLIENT_INSTALL_PATH=~/.local/share/Steam SteamAppId=304050 SteamGameId=304050 \
WINEDEBUG=+timestamp,+pid,+process,+wintrust,+file \
  "<proton>/proton" waitforexitandrun "$PWD/xldr_Trove_GL_loader_x64.exe" trove_x64.exe
```

**Builds tested, all exit 1048 (fresh prefixes):** Proton Hotfix `hotfix-20261110`, Proton Experimental `experimental-11.0-20261112`, Proton `11.0-2e`, Proton `10.0-4b`, GE-Proton11-12, GE-Proton11-7, GDK-Proton11-7, GE-Proton10-34, dwproton-10.0-16, UMU-Proton-10.0-4.
Also no change with `PROTON_USE_WINED3D=1`, or after replacing the prefix's symlinked system32 DLLs (including `ntoskrnl.exe`) with real copies.

**What the loader does just before exiting** (`+file,+wintrust,+process`, loader pid only):

```
NtCreateFile L"\\Device\\WinD"
NtCreateFile L"\\Device\\KsDumper"
NtCreateFile L"\\Device\\HarddiskVolume1\\windows\\system32\\ntoskrnl.exe"
NtCreateFile L"\\??\\C:\\windows\\system32\\wintrust.dll"
NtCreateFile L"\\??\\C:\\windows\\system32\\catroot"
NtCreateFile L"\\??\\C:\\windows\\system32\\catroot\\{127d0a1d-4ef2-11d1-8608-00c04fc295ee}"
trace:wintrust:CryptCATAdminAcquireContext2 ... L"SHA256" ...
trace:wintrust:CryptCATAdminEnumCatalogFromHash ... 32 0 0000000000000000
trace:wintrust:CryptCATAdminAcquireContext {f750e6c3-38ee-11d1-85e5-00c04fc295ee} 0
trace:wintrust:CryptCATAdminEnumCatalogFromHash ... 20 0 0000000000000000
trace:crypt:CryptAcquireContextW (..., L"Microsoft Base Cryptographic Provider v1.0", 1, f0000000)
err:ntdll:NtQueryInformationToken Unhandled token information class TokenPrivateNameSpace
   (~1 s later)
trace:process:NtTerminateProcess handle 0xffffffffffffffff, exit_code 1048
```

**Upstream WineHQ 11.0** (flatpak `org.winehq.Wine`, same Trove files, same repro command with `wine` instead of `proton`): the loader opens the same `\Device\WinD`, `\Device\KsDumper`, `ntoskrnl.exe`, `hal.dll` and `drivers\mountmgr.sys`, but **makes no `CryptCATAdmin*` calls**. It goes on to start `trove_x64.exe` and `XIGNCODE\Client\1__live\xxd-0.xem`. With a real Glyph login the game runs normally this way, with DXVK enabled for `trove_x64.exe` only.

So something Proton-specific makes the loader take the catalog-verification path that upstream Wine doesn't trigger. We couldn't narrow down what.
