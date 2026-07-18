import assert from "node:assert/strict";
import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { test } from "node:test";

const root = new URL("..", import.meta.url).pathname.replace(/^\/([A-Za-z]:\/)/, "$1");
const path = (...parts) => join(root, ...parts);

test("package exposes reusable Retro QQ Skin files", () => {
  for (const relative of [
    "assets/qq-skin.css",
    "assets/renderer-inject.js",
    "assets/theme.json",
    "assets/qq-reference.png",
    "assets/codex-pet.png",
    "assets/retro-window-frame.png",
    "assets/qq-avatar.png",
    "scripts/install-qq-skin.ps1",
    "scripts/start-qq-skin.ps1",
    "scripts/restore-qq-skin.ps1",
    "scripts/tray-qq-skin.ps1",
    "scripts/verify-qq-skin.ps1",
    "README.md",
  ]) {
    assert.equal(existsSync(path(relative)), true, `${relative} should exist`);
  }
});

test("Windows runtime uses independent QQ state and script names", () => {
  const common = readFileSync(path("scripts/common-windows.ps1"), "utf8");
  assert.match(common, /CodexQQSkin/);
  assert.match(common, /start-qq-skin\.ps1/);
  assert.match(common, /restore-qq-skin\.ps1/);
  assert.match(common, /tray-qq-skin\.ps1/);
  assert.doesNotMatch(common, /CodexDreamSkin/);
});

test("injector builds the QQ renderer payload", () => {
  const injector = readFileSync(path("scripts/injector.mjs"), "utf8");
  assert.match(injector, /__QQ_SKIN_CSS_JSON__/);
  assert.match(injector, /__QQ_SKIN_ART_JSON__/);
  assert.match(injector, /__QQ_SKIN_PET_JSON__/);
  assert.match(injector, /__QQ_SKIN_RETRO_FRAME_JSON__/);
  assert.match(injector, /__QQ_SKIN_QQ_AVATAR_JSON__/);
  assert.doesNotMatch(injector, /__DREAM_CSS_JSON__/);
});
