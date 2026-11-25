const fs = require('node:fs');
const path = require('node:path');
const luaparse = require('luaparse');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');

process.chdir(path.join(__dirname, '..'));
// Addon Lua files live at the repository root (CurseForge packages the root as the addon folder).
for (const dir of ['.', 'tests']) {
  for (const name of fs.readdirSync(dir).filter(name => name.endsWith('.lua'))) {
    luaparse.parse(fs.readFileSync(path.join(dir, name), 'utf8'), { luaVersion: '5.1' });
    console.log(`Lua 5.1 syntax OK: ${dir}/${name}`);
  }
}
// A release must carry one version everywhere: TOC, Lua, package.json and the newest changelog section.
const versions = {
  'PreflightForever.toc': fs.readFileSync('PreflightForever.toc', 'utf8').match(/^## Version: (.+)$/m)?.[1].trim(),
  'Main.lua ns.version': fs.readFileSync('Main.lua', 'utf8').match(/^ns\.version = "([^"]+)"/m)?.[1],
  'package.json': JSON.parse(fs.readFileSync('package.json', 'utf8')).version,
  'CHANGELOG.md': fs.readFileSync('CHANGELOG.md', 'utf8').match(/^## (\S+)/m)?.[1],
};
if (Object.values(versions).includes(undefined) || new Set(Object.values(versions)).size !== 1) {
  throw new Error(`Version mismatch: ${JSON.stringify(versions)}`);
}
console.log(`Version ${versions['PreflightForever.toc']} matches in TOC, Main.lua, package.json and CHANGELOG.md`);

for (const file of ['tests/model_spec.lua', 'tests/api_spec.lua', 'tests/timings_spec.lua', 'tests/routes_spec.lua', 'tests/tracker_spec.lua', 'tests/integration_spec.lua', 'tests/ui_spec.lua']) {
  if (!fs.existsSync(file)) throw new Error(`Missing test: ${file}`);
  const state = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(state);
  if (lauxlib.luaL_dofile(state, to_luastring(file)) !== lua.LUA_OK) {
    throw new Error(to_jsstring(lua.lua_tostring(state, -1)));
  }
  lua.lua_close(state);
}
