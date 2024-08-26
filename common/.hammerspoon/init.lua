hs.hotkey.bind('alt-ctrl', '`', hs.toggleConsole)

HS_LUA_ROOT = os.getenv("HOME") .. "/.hammerspoon/lua"

-- I don't have a /usr/local/share/lua.  (Maybe I would if I used
-- Homebrew.)  Replace it with the Lua that I install in
-- ~/.hammerspoon because MacPorts doesn't (yet) ship Lua 5.4, and
-- that is the Lua version Hammerspoon uses as of this writing.
package.path = package.path:gsub('/usr/local', HS_LUA_ROOT)
package.cpath = package.cpath:gsub('/usr/local', HS_LUA_ROOT)
-- Fennel expects the "arg" table to exist, which (I think) is where
-- argv is stored in Lua.
arg = {}
fennel = require 'fennel'
table.insert(package.loaders or package.searchers, fennel.searcher)
init_fennel = require 'init-fennel'
