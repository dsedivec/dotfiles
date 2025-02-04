;;; Utilities

(lambda currently-dark? []
  (let [(_ result)
        (hs.osascript.applescript (.. "tell application \"System Events\""
                                      " to tell appearance preferences"
                                      " to return dark mode"))]
    result))

;; Each function is called with a single boolean is-dark whenever the
;; theme is switched.
(var dark-mode-hooks [])

(lambda run-dark-mode-hooks [?is-dark]
  (let [is-dark (if (= ?is-dark nil)
                    (currently-dark?)
                    ?is-dark)]
    (print "Running dark mode hooks")
    (each [_ hook (ipairs dark-mode-hooks)]
      (hook is-dark))))

(lambda get-macos-theme-switch-capabilities []
  (let [os-vers (hs.host.operatingSystemVersion)
        {:major major :minor minor} os-vers]
    (if (and (= major 10) (= minor 14))
        ;; Mojave has dark node but no automatic switching.
        :manual
        (or (>= major 11) (and (= major 10) (>= minor 15)))
        ;; Catalina introduced automatic switching.
        :automatic
        ;; No dark mode at all, AFAIK.
        nil)))


;;; Mojave support

;; No automatic theme switching by the OS, so we do it at
;; sunrise/sunset ourselves.

;; Max cached location age in seconds.
(local max-cached-location-age 1800)

(var cached-location nil)

(lambda get-location [callback ?force-refresh]
  (if (and cached-location
           (not ?force-refresh)
           (<= (- (os.time) cached-location.time) max-cached-location-age))
      (callback cached-location.loc)
      (let [ipinfo-loc-pattern "(%-?%d+%.%d+)[^%d]-(%-?%d+%.%d+)"
            ;; Wrap callback to call the original callback after we
            ;; cache the location.
            callback (lambda [loc]
                       (set cached-location {:time (os.time) :loc loc})
                       (callback loc))
            ;; I used to check hs.location.servicesEnabled() and
            ;; hs.location.authorizationStatus() here, but the
            ;; authorization status was apparently never quite
            ;; reliable (returned "undefined" sometimes for no
            ;; apparent reason).  I think the location module isn't
            ;; initialized properly until you get the location for the
            ;; first time, so now we just skip straight to that.
            ;;
            ;; Actually, there is something *deeply fucked* about
            ;; hs.location.get().  The thing you run after you call it
            ;; is... fucking skipped?????  Hammerspoon smfh.
            ;;
            ;; Call it twice.  One of them might work!
            loc-serv-loc (or (hs.location.get)
                             (hs.location.get))]
        (if loc-serv-loc
            (callback loc-serv-loc)
            (hs.http.asyncGet "https://ipinfo.io"
                              {"Accept" "application/json"}
                              (lambda [status body ?_]
                                (if (= status 200)
                                    (let [resp (hs.json.decode body)

                                          (lat lon)
                                          (string.match resp.loc
                                                        ipinfo-loc-pattern)]
                                      (callback {:latitude (tonumber lat)
                                                 :longitude (tonumber lon)}))
                                    (hs.showError (.. "ipinfo.io returned "
                                                      status)))))))))

(lambda get-utc-offset-hours []
  (let [now (os.time)
        local-tm (os.date "*t" now)
        utc-tm (os.date "!*t" now)]
    (- local-tm.hour utc-tm.hour)))

(lambda get-tomorrow []
  "Return a Lua time struct for some time tomorrow."
  (let [struct-now (os.date "*t")]
    ;; Looking at the docs for mktime(3), it seems like I can probably
    ;; get a "calendar time" (AKA Unix time, AKA the result of Lua's
    ;; os.time) by just blindly incrementing tm_mday, and pointing the
    ;; hour into the middle of the day to avoid DST problems.  mktime
    ;; is supposed to clean up the values into proper ranges.
    (tset struct-now :day (+ struct-now.day 1))
    (tset struct-now :hour 12)
    ;; This is probably not supported by Lua, but -1 is supposed to
    ;; tell mktime to figure out DST for itself.
    (tset struct-now :isdst -1)
    ;; Round trip through mktime to fix the fields.
    (os.date "*t" (os.time struct-now))))

(lambda set-dark-mode [is-dark]
  (when (not= is-dark (currently-dark?))
    (print (.. "Changing theme to " (if is-dark "dark" "light") " mode"))
    (hs.osascript.applescript (.. "tell application \"System Events\""
                                  " to tell appearance preferences"
                                  " to set dark mode to "
                                  (if is-dark "true" "false")))
    (run-dark-mode-hooks is-dark)))

(var theme-switch-timer nil)

(lambda auto-set-dark-mode-and-schedule-change []
  (print "Entered auto-set-dark-mode-and-schedule-change")
  (get-location
   (lambda [loc]
     (let [now (os.time)
           {:latitude lat :longitude lon} loc
           utc-offset (get-utc-offset-hours)
           sunrise (hs.location.sunrise lat lon utc-offset)
           sunset (hs.location.sunset lat lon utc-offset)
           is-dark (not (and (>= now sunrise) (< now sunset)))
           next-run (if is-dark
                        (if (< now sunrise)
                            ;; Sunrise today
                            sunrise
                            ;; Sunrise tomorrow
                            (hs.location.sunrise lat lon utc-offset
                                                 (get-tomorrow)))
                        ;; Sunset today
                        sunset)
           next-run-secs (math.max (- next-run (os.time)) 0)]
       (print (.. "Sunrise is " (os.date "%c" sunrise) " " sunrise))
       (print (.. "Sunset is  " (os.date "%c" sunset)  " " sunset))
       (print (.. "Now is     " (os.date "%c" now)     " " now))
       (print (.. "Dark mode should be " (tostring is-dark)))
       (set-dark-mode is-dark)
       (set theme-switch-timer
            (hs.timer.doAfter next-run-secs
                              auto-set-dark-mode-and-schedule-change))
       (print (.. "Scheduled theme switch for "
                  (os.date "%c" next-run)
                  " (" (tostring next-run-secs) " seconds)"))
       (print (.. "Timer is " (tostring theme-switch-timer)))))))

(lambda stop-timer []
  (when theme-switch-timer
    (print "Stopping auto dark mode timer")
    (theme-switch-timer:stop)
    (set theme-switch-timer nil)))

;; This is just for debugging.
(lambda get-timer []
  theme-switch-timer)

(lambda update-auto-dark-mode-and-timer []
  (print "Restarting auto dark mode")
  (print (.. "Timer is "
             (if theme-switch-timer
                 (.. (tostring theme-switch-timer)
                     " and is "
                     (if (theme-switch-timer:running)
                         (.. "running and set for "
                             (tostring (theme-switch-timer:nextTrigger))
                             " second(s)")
                         "NOT RUNNING"))
                 "nil/false")))
  (stop-timer)
  (auto-set-dark-mode-and-schedule-change))

;; We'll update the theme when we wake up, in case you've just
;; traveled to a new time zone.

(var theme-switch-caffeinate-watcher nil)

(lambda handle-caffeinate-event [event]
  (print "Auto dark mode got caffeinate event")
  (when (= event hs.caffeinate.watcher.systemDidWake)
    (print "Dispatching")
    (update-auto-dark-mode-and-timer)))

(lambda stop-caffeinate-watcher []
  (when theme-switch-caffeinate-watcher
    (print "Auto dark mode stopping caffeinate watcher")
    (theme-switch-caffeinate-watcher:stop)
    (set theme-switch-caffeinate-watcher nil)))

(lambda start-caffeinate-watcher  []
  (stop-caffeinate-watcher)
  (set theme-switch-caffeinate-watcher
       (hs.caffeinate.watcher.new handle-caffeinate-event))
  (theme-switch-caffeinate-watcher:start))


;;; System theme switch notification, Mojave and later

;; The OS auto-switches and we just listen for an event.  This code
;; was originally derived from
;; https://github.com/Hammerspoon/hammerspoon/issues/2386#issuecomment-643715994.

(fn react-to-system-theme-switch []
  (run-dark-mode-hooks))

(var notification-watcher nil)

(lambda stop-notification-watcher []
  (when notification-watcher
    (print "Stopping notification watcher")
    (notification-watcher:stop)
    (set notification-watcher nil)))

(lambda start-notification-watcher []
  (stop-notification-watcher)
  (print "Starting notification watcher")
  (set notification-watcher
       (hs.distributednotifications.new react-to-system-theme-switch
                                        "AppleInterfaceThemeChangedNotification"))
  (notification-watcher:start))


;;; Public API

(lambda start-auto-dark-mode [force-manual]
  (let [cap (get-macos-theme-switch-capabilities)]
    (assert (or (= cap :manual) (= cap :automatic)))
    (when (or force-manual (= cap :manual))
      (print "Auto-dark mode using its own timer")
      (update-auto-dark-mode-and-timer)
      (start-caffeinate-watcher))
    (start-notification-watcher)))

(lambda stop-auto-dark-mode []
  (let [cap (get-macos-theme-switch-capabilities)]
    (assert (or (= cap :manual) (= cap :automatic)))
    (when (= cap :manual)
      (stop-timer)
      (stop-caffeinate-watcher))
    (stop-notification-watcher)))

{:start            start-auto-dark-mode
 :stop             stop-auto-dark-mode
 :hooks            dark-mode-hooks
 :                 run-dark-mode-hooks
 :currently-dark?  currently-dark?
 :get-timer        get-timer
 :update           update-auto-dark-mode-and-timer}
