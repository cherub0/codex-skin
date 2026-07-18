# Retro QQ Skin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a reusable Windows Codex Retro QQ Skin package and install it locally.

**Architecture:** Copy the proven Windows runtime from Codex Dream Skin, copy QQ Skin renderer/assets, then adapt names, state roots, runtime asset requirements, and wrappers. Verification combines inherited Node tests with PowerShell parse checks and an installer run.

**Tech Stack:** Windows PowerShell 5.1+, Node.js 22+, Chromium DevTools Protocol, CSS/DOM renderer injection.

## Global Constraints

- Target state root is `%LOCALAPPDATA%\CodexQQSkin`.
- Official Store package name remains `OpenAI.Codex`.
- Do not modify official app installation files, `app.asar`, signatures, API keys, or base URLs.
- Runtime must operate on loopback CDP only.
- Package must be reusable from `D:\for_cherub\05.codex\codex-skin`.

---

### Task 1: Seed Package Files

**Files:**
- Create: `assets/*`
- Create: `scripts/*`
- Create: `tests/*`
- Create: root wrapper `.ps1` files
- Create: `README.md`

**Interfaces:**
- Consumes: downloaded reference repositories in `%TEMP%\Codex-Dream-Skin` and `%TEMP%\Codex-QQ-Skin`.
- Produces: a package tree with Dream Windows scripts and QQ assets.

- [ ] Copy `windows/assets`, `windows/scripts`, and `windows/tests` from Dream Skin into the workspace.
- [ ] Replace `assets/dream-skin.css`, `assets/renderer-inject.js`, and `assets/theme.json` with QQ Skin's `qq-skin.css`, `renderer-inject.js`, and `theme.json`.
- [ ] Copy QQ image assets `portal-hero.png`, `codex-pet.png`, `retro-window-frame.png`, and `qq-avatar.png`.
- [ ] Rename `dream-reference.jpg` expectation to a package-local default background copied from `portal-hero.png` as `qq-reference.png`.
- [ ] Add root PowerShell wrappers that call the corresponding scripts.

### Task 2: Adapt Windows Runtime Naming

**Files:**
- Modify: `scripts/common-windows.ps1`
- Modify: `scripts/theme-windows.ps1`
- Modify: `scripts/install-qq-skin.ps1`
- Modify: `scripts/start-qq-skin.ps1`
- Modify: `scripts/restore-qq-skin.ps1`
- Modify: `scripts/tray-qq-skin.ps1`
- Modify: `scripts/verify-qq-skin.ps1`
- Modify: `scripts/injector.mjs`

**Interfaces:**
- Consumes: seeded package tree.
- Produces: Windows runtime that uses `%LOCALAPPDATA%\CodexQQSkin`, QQ asset filenames, and QQ user-facing labels.

- [ ] Rename script filenames from `*-dream-skin.ps1` to `*-qq-skin.ps1`.
- [ ] Replace user-facing `Dream Skin` strings with `Retro QQ Skin` or `QQ Skin`.
- [ ] Replace managed state root `CodexDreamSkin` with `CodexQQSkin`.
- [ ] Replace runtime required files so installation checks for QQ assets and script names.
- [ ] Update theme initialization to read `qq-reference.png` and `theme.json`.
- [ ] Update injector placeholders from Dream-only CSS/art to QQ CSS, art, pet, frame, avatar, and theme placeholders expected by QQ renderer injection.

### Task 3: Documentation and Tests

**Files:**
- Modify: `README.md`
- Modify: `tests/*.mjs`
- Modify: `tests/run-tests.ps1`

**Interfaces:**
- Consumes: adapted runtime.
- Produces: reusable instructions and runnable verification.

- [ ] Write Chinese README with install/start/restore/verify commands and safety notes.
- [ ] Adapt inherited tests to QQ naming and asset requirements.
- [ ] Run `node --test tests/*.mjs` or the included test runner.
- [ ] Run a PowerShell parser check for all `.ps1` scripts.

### Task 4: Install Locally

**Files:**
- Uses: `scripts/install-qq-skin.ps1`

**Interfaces:**
- Consumes: verified package.
- Produces: installed runtime in `%LOCALAPPDATA%\CodexQQSkin` and shortcuts.

- [ ] Run installer from the package directory.
- [ ] If Codex is running, stop and report the installer blocker or rerun after closure when safe.
- [ ] Report installed path, shortcuts, and any failed verification details.
