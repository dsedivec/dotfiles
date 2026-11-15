-- Runs the actual compiled scheduler, never real OS, network, or appearance APIs.
-- Usage: TZ=UTC lua auto-dark-mode-scheduler-test.lua compiled-auto-dark-mode.lua
local compiled = assert(arg[1], 'compiled scheduler path required')
local realos = os
local KEY = 'auto-dark-mode.state.v1'
local function clone(value)
  if type(value) ~= 'table' then return value end
  local copy = {}; for k,v in pairs(value) do copy[k] = clone(v) end; return copy
end
local function epoch(day, hour, month, year)
  return realos.time({year=year or 2026,month=month or 1,day=day or 15,hour=hour or 12,min=0,sec=0})
end
local function create(options)
  options = options or {}
  local s = {now=options.now or epoch(), elapsed=0, timers={}, requests={}, wakes={}, notifications={},
    settings=options.settings or {}, settingsReads=0, settingsWrites=0, dark=options.dark or false,
    reads=0, writes=0, hooks=0, solarCalls={}, options=options}
  local fakeos = {}; for k,v in pairs(realos) do fakeos[k]=v end
  fakeos.time = function(date) return date and realos.time(date) or s.now end
  fakeos.date = function(fmt, when)
    if options.dateLimit and when and math.abs(when)>options.dateLimit then error('synthetic platform calendar range') end
    if options.offset then fmt=fmt:gsub('%%z',function() return options.offset end) end
    if options.zone then fmt=fmt:gsub('%%Z',function() return options.zone end) end
    return realos.date(fmt, when or s.now)
  end
  local function timer(delay, fn, interval)
    assert(type(delay)=='number' and delay>=0, 'invalid timer delay')
    local t={at=s.elapsed+delay, callback=fn, alive=true, interval=interval}
    function t:stop() self.alive=false; return self end
    function t:running() return self.alive end
    function t:nextTrigger() return self.at-s.elapsed end
    s.timers[#s.timers+1]=t; return t
  end
  local function watcher(fn, list)
    local w={callback=fn, alive=false}
    function w:start() self.alive=true; return self end
    function w:stop() self.alive=false; return self end
    list[#list+1]=w; return w
  end
  local function solar(lat,lon,offset,date,hour)
    assert(type(lat)=='number' and type(lon)=='number', 'synthetic coordinates required')
    local d=date or realos.date('*t',s.now)
    s.solarCalls[#s.solarCalls+1]={offset=offset,date=('%04d-%02d-%02d'):format(d.year,d.month,d.day),hour=hour}
    if options.solarError then error('synthetic solar failure') end
    if options.polar then return hour==6 and 'N/R' or 'N/S' end
    local result=realos.time({year=d.year,month=d.month,day=d.day,hour=hour,min=0,sec=0})
    if options.outOfDay then return result+3*86400 end
    return result
  end
  local locator={acquire=function(callback)
    local r={callback=callback,canceled=false}; s.requests[#s.requests+1]=r
    if options.auto then timer(0,function()
      if not r.canceled then
        if options.auto=='success' then callback({latitude=0,longitude=0,source='ipinfo',acquiredAt=s.now,observedAt=s.now},nil)
        else callback(nil,{code='all-sources-failed',failures={}}) end
      end
    end) end
    return function() r.canceled=true end
  end}
  local hs={
    host={operatingSystemVersion=function() return {major=26,minor=0} end},
    settings={get=function(key)
      assert(key==KEY); s.settingsReads=s.settingsReads+1
      if options.readError then error('synthetic settings read failure') end
      return clone(s.settings[key])
    end,set=function(key,value)
      assert(key==KEY); s.settingsWrites=s.settingsWrites+1
      if options.writeError then error('synthetic settings write failure') end
      s.settings[key]=clone(value)
    end},
    location={get=function() return nil end,
      sunrise=function(a,b,c,d) return solar(a,b,c,d,6) end,
      sunset=function(a,b,c,d) return solar(a,b,c,d,18) end},
    http={asyncGet=function() end},
    osascript={applescript=function(script)
      if script:find('to return dark mode',1,true) then s.reads=s.reads+1; return true,s.dark end
      if options.appearanceError then return false,'synthetic appearance error' end
      s.writes=s.writes+1; s.dark=script:find('to set dark mode to true',1,true)~=nil
      return true,s.dark
    end},
    timer={doAfter=function(delay,fn) return timer(delay,fn) end,
      doEvery=function(delay,fn) return timer(delay,fn,delay) end,
      absoluteTime=function() return s.elapsed*1e9 end},
    caffeinate={watcher={systemDidWake=1,new=function(fn) return watcher(fn,s.wakes) end}},
    distributednotifications={new=function(fn) return watcher(fn,s.notifications) end},
  }
  local env=setmetatable({hs=hs,os=fakeos,print=function() end,
    require=function(name) if name=='auto-dark-mode-location' then return locator end; return require(name) end},{__index=_G})
  env._G=env; s.adm=assert(loadfile(compiled,'t',env))()
  table.insert(s.adm.hooks,function() s.hooks=s.hooks+1 end)
  function s:respond(index, location, err)
    assert(self.requests[index], 'live acquisition interface was not called')
    self.requests[index].callback(location,err)
  end
  function s:success(index)
    self:respond(index,{latitude=0,longitude=0,source='ipinfo',acquiredAt=self.now,observedAt=self.now},nil)
  end
  function s:fail(index) self:respond(index,nil,{code='all-sources-failed',failures={}}) end
  function s:running()
    local n=0; for _,t in ipairs(self.timers) do if t.alive then n=n+1 end end; return n
  end
  function s:wake() for _,w in ipairs(self.wakes) do if w.alive then w.callback(1) end end end
  function s:advance(seconds)
    local target=self.elapsed+seconds; local count=0
    while true do
      local nextTimer
      for _,t in ipairs(self.timers) do
        if t.alive and t.at<=target and (not nextTimer or t.at<nextTimer.at) then nextTimer=t end
      end
      if not nextTimer then break end
      count=count+1; assert(count<200000,'zero-delay timer loop')
      local delta=nextTimer.at-self.elapsed; self.now=self.now+delta; self.elapsed=nextTimer.at
      if nextTimer.interval then nextTimer.at=nextTimer.at+nextTimer.interval else nextTimer.alive=false end
      nextTimer.callback()
    end
    self.now=self.now+target-self.elapsed; self.elapsed=target
  end
  return s
end
local passed,failed=0,0
local function check(name,fn)
  local ok,err=pcall(fn)
  if ok then passed=passed+1; print('PASS '..name)
  else failed=failed+1; print('FAIL '..name..'\n  '..tostring(err)) end
end
check('persisted live state survives a simulated offline restart',function()
  local store={}; local first=create({settings=store,now=epoch(15,20)})
  first.adm.start(true); first:success(1)
  assert(store[KEY] and store[KEY].version==1,'successful state was not persisted')
  assert(store[KEY].solar and store[KEY].lastLiveSuccessAt,'solar/freshness metadata missing')
  first.adm.stop()
  local second=create({settings=store,now=epoch(16,20)})
  second.adm.start(true)
  assert(second.dark and second.adm['get-timer'](),'cached coordinates did not immediately restore current-day scheduling')
  assert(second.settings[KEY].solar.date==realos.date('%Y-%m-%d',second.now),'yesterday was not recalculated')
  assert(#second.requests==1,'background refresh was not launched')
end)
check('outage retries use bounded asynchronous backoff without losing transitions',function()
  local seed=create({now=epoch(15,20)}); seed.adm.start(true); seed:success(1); seed.adm.stop()
  local s=create({settings=seed.settings,now=epoch(15,20)})
  s.adm.start(true); s:fail(1)
  assert(s.dark and s.adm['get-timer'](),'failed refresh discarded useful cached scheduling')
  for index,delay in ipairs({30,120,600,1800,3600,3600}) do
    s:advance(delay-1)
    assert(#s.requests==index,'retry fired early or Hammerspoon was blocked')
    s:advance(1)
    assert(#s.requests==index+1,'background retry missing at bounded delay')
    if index<6 then s:fail(index+1) end
  end
  s:success(7)
  local count=#s.requests; s:advance(3600)
  assert(#s.requests==count,'successful refresh did not cancel retry')
end)
check('35-day healthy uptime independently refreshes every local day',function()
  local s=create({now=epoch(),auto='success'}); s.adm.start(true); s:advance(0)
  local initialReads=s.reads; s:advance(60*10)
  assert(s.reads==initialReads,'healthy watchdog queried appearance every minute')
  for day=1,35 do
    s:advance(86400)
    assert(#s.requests>=day+1,'daily background location refresh missing on day '..day)
    assert(s.settings[KEY].solar.date==realos.date('%Y-%m-%d',s.now),'solar date did not advance')
    assert(s.adm['get-timer']() and s.adm['get-timer']():running(),'future transition lost')
    assert(s:running()==2,'duplicate scheduler timers or acquisition work')
  end
  assert(#s.requests<=37,'watchdog requested a fresh location every minute')
end)
check('wake immediately reconciles a missed transition and refreshes once',function()
  local s=create({now=epoch(15,20)}); s.adm.start(true); s:success(1)
  assert(s.dark,'fixture should start at night')
  s.now=epoch(16,8); s:wake()
  assert(not s.dark,'wake did not apply daylight from cached current-day calculations')
  assert(#s.requests==2,'wake did not request a live refresh')
  for _=1,10 do s:wake() end
  assert(#s.requests==2,'clustered wake callbacks overlapped acquisition')
  s:success(2); s:wake()
  assert(#s.requests==2,'clustered wake notifications were not debounced')
end)
check('status labels stale last-known coordinates and contains no location data',function()
  local seed=create({now=epoch(15,12)}); seed.adm.start(true); seed:success(1); seed.adm.stop()
  local s=create({settings=seed.settings,now=epoch(20,20)})
  s.adm.start(true); s:fail(1)
  local status=s.adm.status()
  assert(status.active and status.manual and status.source=='ipinfo','status lost source/lifecycle')
  assert(status.freshness=='stale' and status.solarMode=='calculated','stale coordinate fallback was not identified')
  assert(status.failureCode=='all-sources-failed' and status.retryScheduled and not status.inFlight,'failure/retry status missing')
  local allowed={active=true,manual=true,source=true,freshness=true,solarMode=true,failureCode=true,
    retryScheduled=true,retryInSeconds=true,inFlight=true,failureCount=true,cacheError=true,transitionScheduled=true}
  for key,value in pairs(status) do
    assert(allowed[key] and type(value)~='table','status leaks cache/provider data')
  end
  status.source='mutated'; assert(s.adm.status().source=='ipinfo','status exposes mutable internal state')
  assert(s.dark,'stale coordinates were discarded instead of used approximately')
end)
check('clock jumps rebase an unchanged solar deadline and ignore its old callback',function()
  local s=create({now=epoch(15,12)}); s.adm.start(true); s:success(1)
  local old=s.adm['get-timer'](); s.now=s.now+3*3600; s:advance(60)
  local replacement=s.adm['get-timer']()
  assert(math.abs(replacement:nextTrigger()-(epoch(15,18)-s.now))<1,'clock jump retained a monotonic timer for the old wall time')
  assert(old~=replacement and not old:running(),'clock correction did not replace its old timer')
  old.callback()
  assert(s.adm['get-timer']()==replacement and s:running()==2,'queued old transition orphaned the replacement timer')
  s:advance(replacement:nextTrigger()); assert(s.dark,'rebased sunset did not switch dark mode')
end)
check('manual update permits one coalesced immediate retry while wake respects backoff',function()
  local s=create(); s.adm.start(true); s:fail(1)
  for _=1,5 do s:wake() end
  assert(#s.requests==1,'wake defeated failure backoff')
  s.adm.update(); assert(#s.requests==2,'explicit manual update did not bypass backoff')
  for _=1,5 do s.adm.update() end
  assert(#s.requests==2,'manual updates overlapped acquisition')
  s:fail(2); s.adm.update()
  assert(#s.requests==2,'manual callback cluster repeatedly bypassed backoff')
  s:advance(2); s.adm.update(); assert(#s.requests==3,'later explicit update remained permanently suppressed')
  s:success(3); s:advance(180)
  assert(#s.requests==3 and not s.adm.status().retryScheduled,'canceled retry revived after manual recovery')
end)
check('same-day saved solar fallback avoids per-minute appearance polling',function()
  local seed=create({now=epoch(15,12)}); seed.adm.start(true); seed:success(1); seed.adm.stop()
  local s=create({settings=seed.settings,now=epoch(15,20),solarError=true})
  s.adm.start(true)
  assert(s.dark and s.adm.status().solarMode=='saved','same-day saved events were not used when local calculation failed')
  local reads=s.reads; s:advance(600)
  assert(s.reads==reads,'unavailable tomorrow caused per-minute AppleScript queries')
  s.now=epoch(16,12); s:advance(60)
  assert(s.dark and s.adm.status().solarMode=='unavailable','yesterday absolute events were reused as today')
end)
check('missing malformed and unreadable caches preserve appearance and still retry',function()
  local cases={false,17,'broken',{version=2},{version=1},
    {version=1,location={latitude=0/0,longitude=0,source='ipinfo',acquiredAt=epoch(),observedAt=epoch()}},
    {version=1,solar={date='2026-01-15',zone='UTC',offsetSeconds=0,computedAt=epoch(),sunrise='bad',sunset=math.huge}}}
  for _,record in ipairs(cases) do
    local s=create({settings={[KEY]=record},dark=true}); s.adm.start(true); s:fail(1)
    assert(s.dark and s.writes==0 and s.reads==0,'unusable cache invented appearance/events')
    assert(s.adm.status().retryScheduled and not s.adm['get-timer'](),'unusable cache blocked retry or created a solar timer')
  end
  local s=create({readError=true,dark=true}); s.adm.start(true); s:fail(1)
  assert(s.adm.status().cacheError=='read-failed' and s.dark,'settings read exception escaped')
end)
check('unwritable settings retain usable memory and the last saved record',function()
  local s=create({now=epoch(15,20)}); s.adm.start(true); s:success(1)
  local saved=clone(s.settings[KEY]); s.options.writeError=true
  s:advance(2); s.adm.update(); s:success(2)
  assert(s.adm.status().cacheError=='write-failed' and s.adm['get-timer'](),'write failure destroyed the live schedule')
  assert(s.settings[KEY].lastLiveSuccessAt==saved.lastLiveSuccessAt,'failed write replaced the saved record')
  s.now=epoch(16,12); s:wake()
  assert(not s.dark and s.adm.status().solarMode=='calculated','write failure discarded in-memory coordinates')
  s.options.writeError=false; s:success(3)
  assert(not s.adm.status().cacheError and s.settings[KEY].solar.date==realos.date('%Y-%m-%d',s.now),'later successful persistence did not recover')
end)
check('invalid solar data can be salvaged from valid cached coordinates',function()
  local seed=create(); seed.adm.start(true); seed:success(1); seed.adm.stop()
  seed.settings[KEY].solar={date='not-a-date',sunrise=0/0,sunset=math.huge}
  local s=create({settings=seed.settings,now=epoch(17,20)})
  s.adm.start(true)
  assert(s.dark and s.adm.status().solarMode=='calculated','bad solar metadata discarded valid cached coordinates')
end)
check('saved solar requires the identical local date zone and UTC offset',function()
  local seed=create(); seed.adm.start(true); seed:success(1); seed.adm.stop()
  for _,variant in ipairs({'date','zone','offsetSeconds','sunrise','sunset'}) do
    local store=clone(seed.settings); local solar=store[KEY].solar
    if variant=='date' then solar.date='2000-01-01'
    elseif variant=='zone' then solar.zone='OTHER'
    elseif variant=='offsetSeconds' then solar.offsetSeconds=solar.offsetSeconds+3600
    elseif variant=='sunrise' then solar.sunrise=solar.sunrise+2*86400
    else solar.sunset=solar.sunrise-1 end
    local s=create({settings=store,now=epoch(15,20),solarError=true})
    s.adm.start(true)
    assert(not s.dark and s.writes==0 and s.adm.status().solarMode=='unavailable','incompatible saved solar was accepted: '..variant)
  end
end)
check('polar thrown and out-of-day calculations preserve appearance without a timer loop',function()
  for _,variant in ipairs({'polar','solarError','outOfDay'}) do
    local opts={now=epoch(15,20),dark=true,auto='success'}; opts[variant]=true
    local s=create(opts); s.adm.start(true); s:advance(3600)
    assert(s.dark and s.writes==0 and not s.adm['get-timer'](),'invalid/polar calculation installed a transition')
    assert(s:running()==1 and #s.requests==1,'invalid solar result looped network or timers')
  end
end)
check('35 offline days keep advancing solar dates while retries stay hourly',function()
  local seed=create({now=epoch(15,20)}); seed.adm.start(true); seed:success(1); seed.adm.stop()
  local s=create({settings=seed.settings,now=epoch(15,20),auto='fail'})
  s.adm.start(true); s:advance(0)
  for day=1,35 do
    s:advance(86400)
    assert(s.dark and s.settings[KEY].solar.date==realos.date('%Y-%m-%d',s.now),'offline solar calendar stalled on day '..day)
    assert(s:running()==3 and s.adm.status().retryScheduled,'offline recovery has missing or duplicate timers')
    local count=#s.requests; for _=1,10 do s:wake() end
    assert(#s.requests==count,'daily/wake recovery defeated hourly backoff')
  end
  assert(#s.requests>=35*24 and #s.requests<=35*24+10,'offline retries were unbounded or stopped')
  assert(s.adm.status().freshness=='stale','long-offline location claimed freshness')
end)
check('stop cancels forced-manual resources and rejects every old callback after restart',function()
  local s=create({now=epoch(15,20)}); s.adm.start(true)
  local requests=#s.requests; s.adm.start(true); s.adm.update()
  assert(#s.requests==requests and #s.wakes==1 and #s.notifications==1,'start/update duplicated resources')
  local oldRequest=s.requests[1]; local oldTimers=clone({})
  for _,t in ipairs(s.timers) do oldTimers[#oldTimers+1]=t end
  local oldWake=s.wakes[1]; local oldNotification=s.notifications[1]
  s.adm.stop(); s.adm.stop()
  assert(oldRequest.canceled and s:running()==0 and not oldWake.alive and not oldNotification.alive,'stop left forced-manual work alive')
  s.adm.start(true); local settingsWrites=s.settingsWrites; local hooks=s.hooks
  s:success(1); oldWake.callback(1); oldNotification.callback()
  for _,t in ipairs(oldTimers) do t.callback() end
  assert(s.settingsWrites==settingsWrites and s.hooks==hooks and #s.requests==2,'old lifecycle callbacks mutated the replacement')
  s:success(2); assert(s:running()==2,'restart lost or duplicated scheduling')
  s.adm.stop(); local count=#s.requests; s.adm.update(); s:advance(86400)
  assert(s:running()==0 and #s.requests==count,'stopped public update or stale callback revived work')
end)
check('late retry and completed acquisition callbacks cannot overwrite newer success',function()
  local s=create(); s.adm.start(true); s:fail(1)
  local oldRetry; for _,t in ipairs(s.timers) do if not t.interval and t.alive then oldRetry=t end end
  s.adm.update(); s:success(2)
  oldRetry.callback(); s:fail(1); s:success(1); s:success(2)
  assert(#s.requests==2 and not s.adm.status().retryScheduled and not s.adm.status().failureCode,'stale callback revived retries or changed status')
  assert(s:running()==2,'stale callback duplicated timers')
end)
check('automatic mode retains notification hooks without manual timers',function()
  local s=create(); s.adm.start(false)
  assert(#s.requests==0 and s:running()==0 and #s.wakes==0 and #s.notifications==1,'native mode acquired a manual scheduler')
  s.notifications[1].callback(); assert(s.hooks==1,'native theme notification lost existing hook behavior')
  s.adm['run-dark-mode-hooks'](true); assert(s.hooks==2,'public hook dispatcher changed')
  s.adm.stop(); s.notifications[1].callback(); assert(s.hooks==2,'stopped native callback still ran hooks')
end)
check('hooks cannot throw away a scheduled transition',function()
  local s=create({now=epoch(15,20)}); table.insert(s.adm.hooks,function() error('synthetic hook failure') end)
  s.adm.start(true); s:success(1)
  assert(s.dark and s.hooks==1 and s.adm['get-timer'](),'hook exception stranded scheduling')
end)
check('fractional signed UTC offsets are passed intact to solar calculations',function()
  for offset,expected in pairs({['+0545']=5.75,['-0330']=-3.5,['-0600']=-6}) do
    local s=create({offset=offset}); s.adm.start(true); s:success(1)
    assert(s.solarCalls[1].offset==expected,'fractional/date-wrap offset was truncated: '..offset)
  end
end)
check('tomorrow uses its own normalized calendar date and DST offset',function()
  local s=create({now=epoch(7,20,3,2026)}); s.adm.start(true); s:success(1)
  local tomorrow=epoch(8,12,3,2026); local z=realos.date('%z',tomorrow)
  local sign,h,m=z:match('^([+-])(%d%d)(%d%d)$')
  local expected=(tonumber(h)+tonumber(m)/60)*(sign=='-' and -1 or 1); local seen=false
  for _,call in ipairs(s.solarCalls) do
    if call.date==realos.date('%Y-%m-%d',tomorrow) then
      seen=true; assert(call.offset==expected,'tomorrow reused today UTC offset across DST')
    end
  end
  assert(seen,'tomorrow calculation did not use a normalized calendar date')
  s:advance(s.adm['get-timer']():nextTrigger()); assert(not s.dark,'DST-crossing sunrise was not reached')
end)
check('timezone changes trigger local recomputation and a coalesced refresh',function()
  local s=create(); s.adm.start(true); s:success(1); local calls=#s.solarCalls
  s.options.zone='OTHER'; s:advance(60)
  assert(#s.solarCalls>calls and #s.requests==2,'zone change was ignored')
  assert(s.settings[KEY].solar.zone=='OTHER','zone metadata was not refreshed')
end)
check('platform calendar errors in malformed cached timestamps are contained',function()
  local seed=create(); seed.adm.start(true); seed:success(1); seed.adm.stop()
  seed.settings[KEY].solar.sunrise=1e11; seed.settings[KEY].solar.sunset=1e11+3600
  local s=create({settings=seed.settings,dateLimit=1e10,now=epoch(15,20)})
  s.adm.start(true)
  assert(s.dark and s.adm.status().solarMode=='calculated','platform date error escaped cache validation')
end)
check('saved events are rejected if the current offset differs before a DST change',function()
  local when=epoch(8,1,3,2026); local noon=epoch(8,12,3,2026)
  local seed=create({now=when}); seed.adm.start(true); seed:success(1); seed.adm.stop()
  local s=create({settings=seed.settings,now=when,solarError=true}); s.adm.start(true)
  if realos.date('%z',when)~=realos.date('%z',noon) or realos.date('%Z',when)~=realos.date('%Z',noon) then
    assert(s.adm.status().solarMode=='unavailable' and not s.dark,'saved solar accepted a different current zone/offset signature')
  end
end)
check('a hook stopping startup cannot leave post-stop timers or watchers behind',function()
  local seed=create({now=epoch(15,20)}); seed.adm.start(true); seed:success(1); seed.adm.stop()
  local s=create({settings=seed.settings,now=epoch(15,20)})
  table.insert(s.adm.hooks,function() s.adm.stop() end)
  s.adm.start(true)
  assert(not s.adm.status().active and s:running()==0,'startup continued installing timers after a hook stopped it')
  for _,w in ipairs(s.wakes) do assert(not w.alive,'startup left an orphaned wake watcher') end
  for _,w in ipairs(s.notifications) do assert(not w.alive,'startup left an orphaned notification watcher') end
  assert(#s.requests==0,'startup acquired location after stop')
  local refreshing=create({settings=seed.settings,now=epoch(16,12)})
  refreshing.adm.start(true)
  table.insert(refreshing.adm.hooks,function() refreshing.adm.stop() end)
  refreshing.now=epoch(16,20); refreshing:fail(1)
  assert(not refreshing.adm.status().active and refreshing:running()==0,'failed refresh scheduled a retry after a hook stopped it')
end)
print(('Scheduler: %d passed, %d failed, %d checks'):format(passed,failed,passed+failed))
os.exit(failed==0 and 0 or 1)
