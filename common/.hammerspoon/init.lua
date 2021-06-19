
hs.hotkey.bind('alt-ctrl', '`', hs.toggleConsole)

PLAYER_EVENTS = {PLAY = true; FAST = true; REWIND = true}
MPD_COMMANDS = {PLAY = "toggle"; FAST = "next"; REWIND = "prev"}
VLC_COMMANDS = {PLAY = "play"; FAST = "next"; REWIND = "previous"}
AIRFOIL_EVENTS = {SOUND_UP = "+", SOUND_DOWN = "-"}
DEBUG_TAP = false
tap = hs.eventtap.new({hs.eventtap.event.types.systemDefined}, function(event)
	if DEBUG_TAP then
		print("event tap debug got event:")
		print(hs.inspect.inspect(event:getRawEventData()))
		print(hs.inspect.inspect(event:getFlags()))
		print(hs.inspect.inspect(event:systemKey()))
	end
	local sys_key_event = event:systemKey()
	local delete_event = false
	if not sys_key_event or not sys_key_event.down then
		return false
	elseif PLAYER_EVENTS[sys_key_event.key] and not sys_key_event['repeat']
	then
		print("received media event")
		local _output, status, _type, rc = hs.execute(
			"~/bin/as-mpc " .. MPD_COMMANDS[sys_key_event.key]
		)
		if status and rc == 0 then
			delete_event = true
		end
		-- Only run AppleScript if VLC is running, since to do
		-- otherwise would actually start VLC.
		if hs.appfinder.appFromName("VLC") then
			local script = string.format([[
				tell application "VLC"
				  if current time >= 0 then
				    %s
				    return true
				  end if
				end tell
				return false
			]], VLC_COMMANDS[sys_key_event.key])
			local success, sent_command = hs.osascript.applescript(script)
			if success and sent_command then
				delete_event = true
			end
		end
	elseif AIRFOIL_EVENTS[sys_key_event.key] and event:getFlags().ctrl then
		local script = string.format([[
			if application "Airfoil" is running then
			  tell application "Airfoil"
			    set activeSpeakers to every speaker whose connected is true
			    repeat with aSpeaker in activeSpeakers
			      set aSpeaker's volume to ((aSpeaker's volume) %s 0.05)
			    end repeat
			  end tell
			end if
		]], AIRFOIL_EVENTS[sys_key_event.key])
		hs.osascript.applescript(script)
		delete_event = true
	end
	return delete_event
end)
tap:start()

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
