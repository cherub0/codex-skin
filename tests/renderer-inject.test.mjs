import assert from "node:assert/strict";
import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const here = path.dirname(fileURLToPath(import.meta.url));
const windowsRoot = path.resolve(here, "..");
const template = await fs.readFile(path.join(windowsRoot, "assets", "renderer-inject.js"), "utf8");
const css = await fs.readFile(path.join(windowsRoot, "assets", "qq-skin.css"), "utf8");

for (const placeholder of [
  "__QQ_SKIN_CSS_JSON__",
  "__QQ_SKIN_ART_JSON__",
  "__QQ_SKIN_PET_JSON__",
  "__QQ_SKIN_RETRO_FRAME_JSON__",
  "__QQ_SKIN_QQ_AVATAR_JSON__",
  "__QQ_SKIN_THEME_JSON__",
  "__QQ_SKIN_VERSION_JSON__",
  "__QQ_SKIN_STYLE_REVISION_JSON__",
]) {
  assert.match(template, new RegExp(placeholder));
}

assert.match(template, /__CODEX_QQ_SKIN_STATE__/);
assert.match(template, /cleanup\s*=\s*\(\)\s*=>/);
assert.match(template, /codex-qq-skin-style/);
assert.match(template, /codex-qq-skin-retro-shell/);
assert.match(template, /codex-qq-skin-right-tray/);
assert.match(template, /codex-qq-skin-home-pet/);
assert.match(template, /root\.classList\.add\("codex-qq-skin"\)/);

assert.match(css, /:root\.codex-qq-skin/);
assert.match(css, /#codex-qq-skin-retro-shell/);
assert.match(css, /#codex-qq-skin-home-pet/);
assert.doesNotMatch(
  css,
  /main\.main-surface\s*>\s*header\.app-header-tint\s*\{[^}]*\b(?:position|z-index)\s*:/,
  "The skin must preserve Codex's native fixed header so the side-panel toggle remains reachable.",
);

console.log("PASS: QQ renderer template exposes required payload hooks and chrome IDs.");
