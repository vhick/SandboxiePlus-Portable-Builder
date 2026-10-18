# Sandboxie Plus — Community True-Portable ZIP Builder

**Status:** Tested offline for structure/safety only. The official portable installation, custom launcher and driver cleanup **are not yet Windows-tested**. If a Windows Actions run fails, inspect its logs and do not disable integrity or service checks to force success.

**Upstream:** [sandboxie-plus/Sandboxie](https://github.com/sandboxie-plus/Sandboxie). Initial reviewed version: [`v1.18.8`](https://github.com/sandboxie-plus/Sandboxie/releases/tag/v1.18.8) (October 17, 2026). **Architecture:** Windows x64 and ARM64 if available as a release asset. **Format:** manually triggered GitHub Actions ZIP only. No `.paf.exe` package or permanent install workflow.

## Why this one is different

Unlike VSCodium and YTSage, Sandboxie Plus is a driver-based Windows security utility. Its kernel driver `SbieDrv` and Windows service `SbieSvc` MUST be installed/registered temporarily for actual sandboxing. This is part of the official SandMan behavior, not optional. Administrator permission may be required. We do **not** install/remove drivers from the custom launcher; the official UI owns its driver lifecycle. A clean shutdown is conditional. We never claim zero system remnants.

**Do not use simultaneously with installed Sandboxie Classic or Sandboxie Plus.** The launcher checks whether `SbieDrv` or `SbieSvc` is already registered before proceeding, and fails safely if it is. Do not remove registered services without first checking who owns them.

## First-time setup with GitHub Desktop

1. Create a new empty public repo on https://github.com/new called `SandboxiePlus-Portable-Builder`. Leave README, .gitignore, and license blank.
2. Extract this build kit ZIP into a temporary folder. Its top level contains `.github`, `builder`, `tests`, `README.md` and `START-HERE.txt`.
3. In **GitHub Desktop**: `File > Clone repository`; select the empty repository. Choose any working folder on your PC.
4. In GitHub Desktop click **Repository > Show in Explorer**. Copy the **contents** of the extracted kit (including `.github`) into that working folder. Do not copy the kit ZIP itself.
5. Return to GitHub Desktop, review **Changes**, enter `Add Sandboxie Plus portable builder`, click **Commit to main**, then **Push origin**.
6. On GitHub.com open the new repo > **Actions** > **Build Sandboxie Plus Portable ZIP (Manual)** > **Run workflow**. Choose tag `v1.18.8`, architecture `x64` initially.
7. Once a run **succeeds**, download the artifact, extract its GitHub ZIP wrapper, then extract `SandboxiePlusPortable-1.18.8-x64.zip` into a local folder.
8. Launch the ROOT `SandboxiePlusPortable.exe` (not `App/SandboxiePlus/SandMan.exe`). The native SandMan app asks for administrator approval to load driver/service. Do not launch from a protected location such as `C:\Program Files`.

If the workflow fails, **no usable portable application has been produced**. Download the failed run's logs and inspect before modifying scripts. GitHub Actions downloads and verifies the official release and extracts it via supported Inno Setup `/PORTABLE=1 /CURRENTUSER` mode on a temporary Windows runner.

## Resulting portable ZIP layout

```text
SandboxiePlusPortable/
  SandboxiePlusPortable.exe       <-- always launch here
  App/
    SandboxiePlus/
      SandMan.exe
      SbieDrv.sys
      SbieSvc.exe
      KmdUtil.exe
      (other official program files)
    AppInfo/
      appicon.ico                <-- official icon pinned to release
  Data/
    Settings/
      Sandboxie.ini             <-- preserved / authoritative copy
      Sandboxie-Plus.ini        <-- preserved / authoritative copy
    Sandboxes/                  <-- sandbox file storage
    Logs/
    Cache/                      <-- created on first launch
    Temp/                       <-- created on first launch
  Other/
    PACKAGE-INFO.txt
    LICENSE-LINKS.txt
```

### Why `Sandboxie.ini` is copied temporarily into App

The official Sandboxie Plus portable mode expects `Sandboxie.ini` and `Sandboxie-Plus.ini` **beside `SandMan.exe`**. The official v1.18.8 portable installer initially supplies *empty* files, which the custom launcher initializes on first run. To preserve our `Data` folder through updates, the launcher:

- Starts only if the system does not already register `SbieDrv` or `SbieSvc`.
- Recovers newer INI copies left in `App` by a previous crash into `Data/Settings`.
- Initializes `[GlobalSettings]` and points `FileRootPath` to the current portable folder's `Data/Sandboxes`. It preserves other INI entries, but **per-box overrides can still point outside this directory** and need manual inspection.
- Copies the saved INI files into the application's working directory so the **official portable mode** activates.
- Launches SandMan without a custom kernel driver management routine.
- Every ~1.5 seconds and on normal exit, saves any modified INI settings back to `Data/Settings` using a temporary file and atomic rename when possible.
- Waits for official SandMan driver/service removal and warns if either is still registered. Working INI files remain in `App` on an incomplete shutdown (to support recovery) and should not be manually deleted.
- Removes the *working* INI copies under App only after no Sandboxie driver or service remains registered.

The launcher **does not guarantee recovery from a sudden power failure, a system crash, forced process termination, or a security product blocking drivers**. It avoids aggressive cleanup deliberately.

## Updating/Upgrading safely

1. Close ALL sandboxed programs; close SandMan through Exit rather than just closing/minimizing its window.
2. Confirm Sandboxie Plus has unloaded and **removed** its `SbieDrv`/`SbieSvc` driver/service. Use Sandboxie Plus **Maintenance** for diagnosis, not blind service deletion.
3. Make a full backup of `Data` (especially `Data/Settings` and `Data/Sandboxes`).
4. Run a new manual GitHub Actions build for a reviewed stable release version.
5. Extract the new ZIP elsewhere. **Replace only the old `App` folder and root `SandboxiePlusPortable.exe`**, keeping your existing `Data` untouched.
6. Launch the root launcher. It will update the default global sandbox root to the current portable location. If you configured custom per-box paths, check them after moving between drive letters.

**Never update while SbieDrv or SbieSvc is registered**. Even after the UI closes, Windows may need a reboot to unload them.

## How to verify Windows portability

1. Before launch, record whether `HKLM\SYSTEM\CurrentControlSet\Services\SbieDrv` and `...\SbieSvc` exist. If either exists, do not proceed without determining its owner.
2. Launch root executable. Approve the official driver prompt if you trust the downloaded package. Create a test sandbox and run Notepad in it.
3. Confirm both INI files are written back to `Data/Settings`; confirm the sandbox's `FileRootPath` is beneath `Data/Sandboxes` (look for per-box overrides).
4. Exit all sandboxed apps and explicitly exit SandMan. Confirm driver/service registrations have been removed, and inspect for host AppData and registry remnants. The custom launcher reports a warning if driver/service registration remains.
5. Reopen and confirm the sandbox, preferences and content persist. Run a controlled upgrade, preserving Data.
6. If the driver or service remains installed, pause updates and investigate; do NOT forcibly delete a possibly active security driver.

## Limitations and responsibilities

- We can't guarantee full portability across Windows PCs; kernel drivers require admin privileges and can be blocked by Windows security policy.
- `SbieDrv`/`SbieSvc` are temporary **system registrations**, not user-data files. Other system-managed traces or optional add-ons may remain after closing.
- **Encrypted sandboxes**, add-ons, custom sandbox roots and environment-specific paths need separate portability validation; this kit does not modify their behavior. It does not package an additional ImDisk driver.
- Do not start multiple portable copies concurrently; the launcher checks registered services, but simultaneous launches remain unsupported.
- The kit is community packaging and is not an official Sandboxie Plus or PortableApps.com release. Preserve and follow original licenses.

## Developer sources

- [Repository](https://github.com/sandboxie-plus/Sandboxie)
- [Official installer Inno Setup script](https://github.com/sandboxie-plus/Sandboxie/blob/master/Installer/Sandboxie-Plus.iss)
- [Portable mode explanation from Sandboxie maintainer](https://github.com/sandboxie-plus/Sandboxie/discussions/1752)
- [Portable silent installer parameters](https://github.com/sandboxie-plus/Sandboxie/discussions/1757)
- [Sandboxie.ini format](https://sandboxie-plus.github.io/sandboxie-docs/Content/SandboxieIni/)
- [FileRootPath documentation](https://sandboxie-plus.com/sandboxie/filerootpath/)
- [Conflict between installed and portable modes](https://github.com/sandboxie-plus/Sandboxie/discussions/3884)
