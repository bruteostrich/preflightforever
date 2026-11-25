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
for (const file of ['tests/model_spec.lua', 'tests/api_spec.lua', 'tests/timings_spec.lua', 'tests/routes_spec.lua', 'tests/tracker_spec.lua', 'tests/integration_spec.lua', 'tests/ui_spec.lua']) {
  if (!fs.existsSync(file)) throw new Error(`Missing test: ${file}`);
  const state = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(state);
  if (lauxlib.luaL_dofile(state, to_luastring(file)) !== lua.LUA_OK) {
    throw new Error(to_jsstring(lua.lua_tostring(state, -1)));
  }
  lua.lua_close(state);
}
