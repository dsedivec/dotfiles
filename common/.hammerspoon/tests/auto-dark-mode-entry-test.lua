-- Executes the full compiled entry point with inert OS/hook stubs.
-- Usage: lua auto-dark-mode-entry-test.lua compiled-init-fennel.lua
local compiled = assert(arg[1], 'compiled entry point path required')
local passed, failed = 0, 0
local function check(name, fn)
  local ok, err = pcall(fn)
  if ok then passed = passed + 1; print('PASS '..name)
  else failed = failed + 1; print('FAIL '..name..': '..tostring(err)) end
end
local function boot(options)
  options = options or {}
  local calls, adm = {}, {hooks={}}
  adm.start = function(force) assert(force == true, 'forced manual startup changed'); calls[#calls+1]='start' end
  adm.stop = function() calls[#calls+1]='stop'; if options.stopError then error('synthetic stop failure') end end
  adm['currently-dark?'] = function() return true end
  local inert
  inert = setmetatable({}, {__index=function() return function() return inert end end})
  local prior
  if not options.noPrior then prior = function() calls[#calls+1]='prior' end end
  local hs = {shutdownCallback=prior, configdir='/synthetic/config',
    console=setmetatable({}, {__index=function() return function() calls[#calls+1]='console' end end}),
    logger={new=function() return inert end},
    hotkey={new=function() return inert end, bind=function() end, modal={new=function() return inert end}},
    window={filter={new=function() return inert end, windowFocused='focus',windowUnfocused='unfocus'}}}
  local fakeos = {execute=function(command)
    assert(command == '/synthetic/config/update_macos_theme.sh', 'existing theme command changed')
    calls[#calls+1]='hook'; return true
  end}
  local env = setmetatable({hs=hs,os=fakeos,print=function() end,require=function(name)
    assert(name == 'auto-dark-mode'); return adm
  end}, {__index=_G})
  env._G=env
  local result = assert(loadfile(compiled,'t',env))()
  return hs, adm, calls, result, prior
end
check('full entry preserves manual startup, hook and exported controls', function()
  local _, adm, calls, result = boot()
  assert(calls[1]=='start' and #adm.hooks==1, 'startup/hook registration changed')
  assert(result.adm==adm and type(result['my-dark-mode-hook'])=='function', 'existing entry exports changed')
  local hookCount=0; for _,call in ipairs(calls) do if call=='hook' then hookCount=hookCount+1 end end
  assert(hookCount==1, 'initial hook sync changed')
end)
check('shutdown stops automation before invoking an existing shutdown handler', function()
  local hs, _, calls, _, prior = boot()
  assert(hs.shutdownCallback~=prior, 'entry did not install dark-mode shutdown cleanup')
  hs.shutdownCallback()
  assert(calls[#calls-1]=='stop' and calls[#calls]=='prior', 'shutdown chain order changed')
end)
check('shutdown still invokes the prior handler when scheduler stop throws', function()
  local hs, _, calls = boot{stopError=true}
  assert(pcall(hs.shutdownCallback), 'scheduler cleanup exception escaped the shutdown chain')
  assert(calls[#calls-1]=='stop' and calls[#calls]=='prior', 'prior shutdown handler was skipped')
end)
check('shutdown works without a previous handler', function()
  local hs, _, calls = boot{noPrior=true}
  hs.shutdownCallback(); assert(calls[#calls]=='stop', 'missing prior handler broke cleanup')
end)
print(('Entry: %d passed, %d failed, %d checks'):format(passed,failed,passed+failed))
os.exit(failed==0 and 0 or 1)
