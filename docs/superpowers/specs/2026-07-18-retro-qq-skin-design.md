# Retro QQ Skin Design

## Goal

Build a reusable Windows skin package for the Codex desktop IDE that applies a retro QQ-style interface, then install it on this machine after the package is created.

## Scope

The package targets Windows and the official Microsoft Store `OpenAI.Codex` package. It must not modify the official app installation, `app.asar`, signatures, API keys, or base URLs. The runtime should operate through the Chromium DevTools Protocol on loopback only, following the Windows safety model from Codex Dream Skin.

## Approach

Use the Windows runtime, installer, launcher, restore, tray, verification, UTF-8, image metadata, and CDP injector scripts from `Fei-Away/Codex-Dream-Skin`. Use the retro QQ visual assets, CSS, theme metadata, and renderer injection logic from `zhulin025/Codex-QQ-Skin`.

The local package is independently named `Codex Retro QQ Skin`. Its state root is `%LOCALAPPDATA%\CodexQQSkin`, so it does not collide with `CodexDreamSkin`. User-facing shortcuts, messages, script names, mutex names, style IDs, and state keys should use QQ Skin naming where practical.

## Package Layout

- `assets/`: reusable visual and injection assets.
- `scripts/`: Windows install, start, restore, tray, verify, theme, config, metadata, and injector scripts.
- `tests/`: focused Node tests inherited from the Windows/Dream and QQ packages where they remain applicable.
- `README.md`: Windows usage instructions in Chinese.
- `Install Codex Retro QQ Skin.ps1`, `Start Codex Retro QQ Skin.ps1`, `Restore Codex Retro QQ Skin.ps1`, `Verify Codex Retro QQ Skin.ps1`: root convenience wrappers.

## Behavior

The installer validates that the official Store Codex app is installed and closed, validates Node.js, copies the runtime into `%LOCALAPPDATA%\CodexQQSkin\engine`, initializes the active theme store, backs up `~/.codex/config.toml`, and creates desktop/start menu shortcuts.

The start script launches official Codex with a local CDP port, starts the injector watcher, and injects the QQ renderer payload. The restore script stops the recorded injector, removes injected state, and restores the saved base Codex appearance when requested. The verification script checks runtime files, app identity, active theme files, and live injection when requested.

After package creation, run the installer automatically from the local package.

## Visual Design

The visual layer uses the QQ skin's blue-silver retro title bar, toolbar strip, side chrome, home pet, QQ-style avatar/status panel, right companion tray, and classic three-pane task layout. The default appearance should favor the classic light blue-silver QQ look while preserving adaptive behavior for Codex routes and shell appearance.

## Testing

Run the inherited Windows/Node test suite after adapting names and assets. Also run a PowerShell syntax parse over all `.ps1` files. If installation cannot complete because Codex or Windows Store app state is unavailable, report the exact blocker.

## Constraints

- Windows PowerShell scripts must avoid destructive operations outside `%LOCALAPPDATA%\CodexQQSkin`.
- No shell-built recursive deletion across Windows shells.
- Do not require users to modify the official Codex app.
- Keep generated package files reusable from the workspace directory.
