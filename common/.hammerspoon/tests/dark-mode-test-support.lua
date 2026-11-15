-- Synthetic OS boundary for the real compiled scheduler + locator + entry.
-- This file never loads hs, shells out, performs network I/O or writes settings.
local M, realos = {}, os
M.key = 'auto-dark-mode.state.v1'
function M.clone(value)
  if type(value)~='table' then return value end
  local copy={}; for k,v in pairs(value) do copy[k]=M.clone(v) end; return copy
end
function M.epoch(day,hour,minute,month,year)
  return realos.time{year=year or 2026,month=month or 1,day=day or 15,hour=hour or 12,min=minute or 0,sec=0,isdst=false}
end
M.bodies={ipinfo='{"loc":"0,0"}', ipwhois='{"success":true,"latitude":8,"longitude":-9}'}
local fixtures={
  [M.bodies.ipinfo]={loc='0,0'},
  [M.bodies.ipwhois]={success=true,latitude=8,longitude=-9},
  ['{"loc":"999,0"}']={loc='999,0'},
  ['{"success":false}']={success=false},
}
function M.create(paths,o)
  o=o or {}
  assert(realos.date('%z',M.epoch())=='+0000','integration harness must run with TZ=UTC')
  local s={now=o.now or M.epoch(),elapsed=0,timers={},tasks={},trackers={},wakes={},notifications={},
    settings=o.settings or {},dark=o.dark or false,reads=0,writes=0,settingsWrites=0,hooks=0,
    hookCommands=0,logs={},solarCalls={},nativeGets=0,nativeNews=0,maxTasks=0,priorShutdowns=0,o=o}
  local function variable(value,when,default)
    if type(value)=='function' then return value(when) end
    if value~=nil then return value end
    return default
  end
  local function offset(when) return variable(o.offset,when,0) end
  local fakeos={}
  fakeos.time=function(d)
    if not d then return math.floor(s.now) end
    local copy=M.clone(d); copy.isdst=false
    local utc=realos.time(copy); local guess=utc
    for _=1,3 do guess=utc-offset(guess) end
    return guess
  end
  fakeos.date=function(fmt,when)
    fmt=fmt or '%c'; when=when or s.now
    if fmt:sub(1,1)=='!' then return realos.date(fmt,when) end
    local off=offset(when)
    local text=('%s%02d%02d'):format(off<0 and '-' or '+',math.floor(math.abs(off)/3600),math.floor(math.abs(off)%3600/60))
    fmt=fmt:gsub('%%z',function() return text end):gsub('%%Z',function() return variable(o.zone,when,'UTC') end)
    return realos.date('!'..fmt,when+off)
  end
  fakeos.execute=function(command)
    assert(command=='/synthetic/config/update_macos_theme.sh','unexpected shell execution')
    s.hookCommands=s.hookCommands+1; return true
  end
  s.clock=fakeos
  local function timer(delay,fn,interval)
    assert(type(delay)=='number' and delay>=0,'invalid delay')
    local t={at=s.elapsed+delay,callback=fn,interval=interval,alive=true,id=#s.timers+1}
    function t:stop() self.alive=false; return self end
    function t:running() return self.alive end
    function t:nextTrigger() return self.at-s.elapsed end
    s.timers[#s.timers+1]=t; return t
  end
  s.after=function(delay,fn) return timer(delay,fn) end
  local function watcher(fn,list)
    local w={callback=fn,alive=false}
    function w:start() self.alive=true; return self end
    function w:stop() self.alive=false; return self end
    list[#list+1]=w; return w
  end
  local function solar(lat,lon,off,d,rise)
    assert(type(lat)=='number' and type(lon)=='number')
    s.solarCalls[#s.solarCalls+1]={offset=off,date=('%04d-%02d-%02d'):format(d.year,d.month,d.day)}
    if o.solarError then error('synthetic solar failure') end
    if o.polar then return 'N/R' end
    -- Deliberately different synthetic days for the two provider fixtures.
    local hour=(lat==8 and 7 or 6)+(rise and 0 or 12)
    return fakeos.time{year=d.year,month=d.month,day=d.day,hour=hour,min=0,sec=0}
  end
  local location={
    servicesEnabled=function() return o.enabled~=false end,
    authorizationStatus=function() return o.authorization or 'denied' end,
    get=function() s.nativeGets=s.nativeGets+1; return o.nativeFix end,
    new=function()
      s.nativeNews=s.nativeNews+1
      local tracker={alive=false,stopped=0}
      function tracker:callback(...) assert(select('#',...)==1); self.fn=select(1,...); return self end
      function tracker:startTracking() self.alive=true; return self end
      function tracker:stopTracking() self.alive=false; self.stopped=self.stopped+1; return self end
      s.trackers[#s.trackers+1]=tracker; return tracker
    end,
    sunrise=function(a,b,c,d) return solar(a,b,c,d,true) end,
    sunset=function(a,b,c,d) return solar(a,b,c,d,false) end,
    start=function() error('shared location tracking must not be started') end,
    stop=function() error('shared location tracking must not be stopped') end,
  }
  local hs={configdir='/synthetic/config',location=location,
    host={operatingSystemVersion=function() return {major=26,minor=0} end},
    settings={get=function(key) assert(key==M.key); return M.clone(s.settings[key]) end,
      set=function(key,value) assert(key==M.key); s.settingsWrites=s.settingsWrites+1; s.settings[key]=M.clone(value) end},
    timer={doAfter=function(d,f) return timer(d,f) end,doEvery=function(d,f) return timer(d,f,d) end,
      absoluteTime=function() return s.elapsed*1e9 end},
    osascript={applescript=function(script)
      if script:find('to return dark mode',1,true) then s.reads=s.reads+1; return true,s.dark end
      assert(script:find('to set dark mode to ',1,true),'unexpected AppleScript')
      s.writes=s.writes+1; s.dark=script:find('to set dark mode to true',1,true)~=nil
      return true,s.dark
    end},
    caffeinate={watcher={systemDidWake=1,new=function(fn) return watcher(fn,s.wakes) end}},
    distributednotifications={new=function(fn) return watcher(fn,s.notifications) end},
    json={decode=function(body) return M.clone(fixtures[body]) end},
    task={new=function(path,callback,args)
      assert(path=='/usr/bin/curl' and args[1]=='-q','unexpected task transport')
      local source=args[#args]:find('ipinfo.io',1,true) and 'ipinfo' or 'ipwhois'
      local response=variable(o.http,s.now,{})[source] or {exit=7,status=0}
      local task={callback=callback,source=source,args=args,alive=false,terminated=0,response=response}
      function task:emit(exit,body,status)
        self.alive=false
        if self.callback then self.callback(exit,(body or '')..'\n'..('%03d'):format(status or 0),'synthetic private stderr') end
      end
      function task:setCallback(fn) self.callback=fn; return self end
      function task:start()
        if response.startFalse then return false end
        self.alive=true
        local count=0; for _,t in ipairs(s.tasks) do if t.alive then count=count+1 end end
        s.maxTasks=math.max(s.maxTasks,count)
        if not response.hang then self.event=timer(response.delay or 0,function()
          self:emit(response.exit or 0,response.body,response.status or 200)
        end) end
        return self
      end
      function task:terminate()
        self.terminated=self.terminated+1; self.alive=false
        if self.event then self.event:stop() end
        if o.callbackOnTerminate~=false then self:emit(15,'synthetic terminated body',0) end
        return self
      end
      s.tasks[#s.tasks+1]=task; return task
    end},
    execute=function() error('blocking hs.execute used') end,
    http={get=function() error('blocking HTTP used') end},
  }
  local inert
  inert=setmetatable({}, {__index=function() return function() return inert end end})
  hs.console=setmetatable({}, {__index=function() return function() end end})
  hs.logger={new=function() return inert end}
  hs.hotkey={new=function() return inert end,bind=function() end,modal={new=function() return inert end}}
  hs.window={filter={new=function() return inert end,windowFocused='focus',windowUnfocused='unfocus'}}
  s.hs=hs
  function s:boot(entry)
    local modules,env={}
    env=setmetatable({hs=hs,os=fakeos,print=function(...) self.logs[#self.logs+1]={...} end,
      require=function(name)
        local path=({['auto-dark-mode-location']=paths.locator,['auto-dark-mode']=paths.scheduler})[name]
        assert(path,'unexpected module: '..name)
        if not modules[name] then modules[name]=assert(loadfile(path,'t',env))() end
        return modules[name]
      end}, {__index=_G})
    env._G=env; self.env=env
    if entry then
      hs.shutdownCallback=function() self.priorShutdowns=self.priorShutdowns+1 end
      self.entry=assert(loadfile(paths.entry,'t',env))(); self.adm=self.entry.adm
    else self.adm=env.require('auto-dark-mode'); self.adm.start(true) end
    table.insert(self.adm.hooks,function() self.hooks=self.hooks+1 end)
    return self.adm
  end
  function s:advance(seconds)
    local target=self.elapsed+seconds; local calls=0
    while true do
      local nextTimer
      for _,t in ipairs(self.timers) do
        if t.alive and t.at<=target and (not nextTimer or t.at<nextTimer.at or (t.at==nextTimer.at and t.id<nextTimer.id)) then nextTimer=t end
      end
      if not nextTimer then break end
      calls=calls+1; assert(calls<200000,'timer storm')
      self.now=self.now+nextTimer.at-self.elapsed; self.elapsed=nextTimer.at
      if nextTimer.interval then nextTimer.at=nextTimer.at+nextTimer.interval else nextTimer.alive=false end
      nextTimer.callback()
    end
    self.now=self.now+target-self.elapsed; self.elapsed=target
  end
  function s:wake() for _,w in ipairs(self.wakes) do if w.alive then w.callback(1) end end end
  function s:emitNative(fixes)
    for _,t in ipairs(self.trackers) do if t.alive and t.fn then t.fn(t,'didUpdateLocations',fixes) end end
  end
  function s:live()
    local n=0; for _,t in ipairs(self.timers) do if t.alive then n=n+1 end end; return n
  end
  function s:assertCurrent()
    local hour=tonumber(fakeos.date('%H',self.now))+tonumber(fakeos.date('%M',self.now))/60
    local source=self.adm.status().source; local rise=(source=='ipwhois') and 7 or 6; local sunset=rise+12
    assert(self.dark==(hour<rise or hour>=sunset),'wrong current synthetic appearance')
    local d=fakeos.date('*t',self.now)
    local nextHour=hour<rise and rise or hour<sunset and sunset or rise
    if hour>=sunset then d.day=d.day+1 end
    d.hour=nextHour; d.min=0; d.sec=0
    local t=assert(self.adm['get-timer'](),'next solar transition missing')
    assert(t:running() and math.abs(t:nextTrigger()-(fakeos.time(d)-self.now))<1.01,'wrong next solar transition')
    assert(self.maxTasks<=1,'overlapping provider tasks')
  end
  return s
end
return M
