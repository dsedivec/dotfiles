;; Solar scheduling owns cache/recovery policy; acquisition owns bounded I/O.
;; Offline policy: recompute today's events from the last-known coordinates.
;; Fixes older than 24h are explicitly approximate/stale, but remain useful
;; indefinitely while offline (they cannot account for unobserved travel).
;; If calculation fails, saved absolute events are usable only on their own
;; local date with the same zone/UTC offset. Otherwise leave appearance alone.
;; hs.settings is local persistent preferences, NOT encrypted secret storage.
;; Never log the cache: it contains location data.
(local locator (require :auto-dark-mode-location))
(local settings-key "auto-dark-mode.state.v1")
(local stale-after 86400)
(local allowed-sources {:corelocation true :ipinfo true :ipwhois true})

(var dark-mode-hooks [])
(var active false)
(var manual false)
(var generation 0)
(var loaded false)
(var state {:version 1})
(var settings-error nil)
(var theme-switch-timer nil)
(var transition-at nil)
(var transition-id 0)
(var cancel-acquisition nil)
(var request-id 0)
(var in-flight false)
(var reconcile nil)
(var request-refresh nil)
(var retry-timer nil)
(var retry-at nil)
(var retry-id 0)
(var failures 0)
(var last-error nil)
(var watchdog-timer nil)
(var last-attempt nil)
(var last-wall nil)
(var last-monotonic nil)
(var last-signature nil)
(var wake-watcher nil)
(var notification-watcher nil)
(var last-wake-at nil)
(var last-manual-at nil)
(var solar-mode :unavailable)
(var last-applied-dark nil)
(local retry-delays [30 120 600 1800 3600])

(fn monotonic [] (/ (hs.timer.absoluteTime) 1000000000))

(fn stop-retry []
  (set retry-id (+ retry-id 1))
  (when retry-timer (retry-timer:stop))
  (set retry-timer nil)
  (set retry-at nil))

(fn schedule-retry []
  (stop-retry)
  (set failures (math.min (+ failures 1) (# retry-delays)))
  (let [delay (. retry-delays failures) life generation id retry-id]
    (set retry-at (+ (monotonic) delay))
    (set retry-timer
         (hs.timer.doAfter delay
           (fn []
             (when (and active manual (= life generation) (= id retry-id))
               (set retry-timer nil)
               (set retry-at nil)
               (request-refresh)))))))

(fn finite? [value]
  (and (= (type value) :number) (= value value) (< (math.abs value) math.huge)))

(fn timestamp? [value]
  (and (finite? value) (> value 0) (<= value 253402300799)))

(fn valid-location? [value now]
  (and (= (type value) :table)
       (finite? value.latitude) (<= (math.abs value.latitude) 90)
       (finite? value.longitude) (<= (math.abs value.longitude) 180)
       (. allowed-sources (or value.source ""))
       (timestamp? value.acquiredAt) (<= value.acquiredAt (+ now 300))
       (timestamp? value.observedAt) (<= value.observedAt (+ value.acquiredAt 300))))

(fn copy-location [value]
  {:latitude value.latitude :longitude value.longitude :source value.source
   :acquiredAt value.acquiredAt :observedAt value.observedAt})

(fn offset-seconds [epoch]
  (let [(sign hours minutes) (string.match (os.date "%z" epoch) "^([+-])(%d%d)(%d%d)$")
        h (tonumber hours) m (tonumber minutes)]
    (when (and sign h m (< m 60) (<= (+ (* h 60) m) 840))
      (* (if (= sign "-") -1 1) (+ (* h 3600) (* m 60))))))

(fn day-context [epoch ?days]
  ;; Do not add 86400, or carry today's isdst flag into tomorrow's mktime.
  (let [d (os.date "*t" epoch)
        noon (os.time {:year d.year :month d.month :day (+ d.day (or ?days 0))
                       :hour 12 :min 0 :sec 0})]
    {:date (os.date "%Y-%m-%d" noon) :zone (os.date "%Z" noon)
     :offsetSeconds (offset-seconds noon) :calendar (os.date "*t" noon)}))

(fn valid-solar-fields? [value now]
  (and (= (type value) :table)
       (= (type value.date) :string) (string.match value.date "^%d%d%d%d%-%d%d%-%d%d$")
       (= (type value.zone) :string) (> (# value.zone) 0) (<= (# value.zone) 64)
       (not (string.find value.zone "[%c]"))
       (finite? value.offsetSeconds) (<= (math.abs value.offsetSeconds) 50400)
       (timestamp? value.computedAt) (<= value.computedAt (+ now 300))
       (timestamp? value.sunrise) (timestamp? value.sunset) (< value.sunrise value.sunset)
       (= (os.date "!%Y-%m-%d" (+ value.sunrise value.offsetSeconds)) value.date)
       (= (os.date "!%Y-%m-%d" (+ value.sunset value.offsetSeconds)) value.date)))

(fn valid-solar? [value now]
  ;; A bounded numeric epoch can still exceed a platform's calendar range.
  (let [(ok valid) (pcall valid-solar-fields? value now)] (and ok valid)))

(fn copy-solar [value]
  {:date value.date :zone value.zone :offsetSeconds value.offsetSeconds
   :computedAt value.computedAt :sunrise value.sunrise :sunset value.sunset})

(fn load-state []
  (when (not loaded)
    (set loaded true)
    (let [(ok saved) (pcall hs.settings.get settings-key)
          now (os.time)]
      (if (not ok) (set settings-error :read-failed)
          (and (= (type saved) :table) (= saved.version 1))
          (do
            ;; Salvage valid independent fields, never copy unknown settings keys.
            (when (valid-location? saved.location now)
              (set state.location (copy-location saved.location)))
            (when (valid-solar? saved.solar now)
              (set state.solar (copy-solar saved.solar)))
            (when (and (timestamp? saved.lastLiveSuccessAt) (<= saved.lastLiveSuccessAt (+ now 300)))
              (set state.lastLiveSuccessAt saved.lastLiveSuccessAt)))
          (not= saved nil) (set settings-error :invalid-cache)))))

(fn persist []
  (let [(ok result) (pcall hs.settings.set settings-key
                          {:version 1
                           :location (and state.location (copy-location state.location))
                           :solar (and state.solar (copy-solar state.solar))
                           :lastLiveSuccessAt state.lastLiveSuccessAt})]
    ;; hs.settings.set normally returns no values, not a success boolean.
    (set settings-error (if (and ok (not= result false)) nil :write-failed))))

(fn calculate-solar [context now]
  (when (and state.location context.offsetSeconds)
    (let [loc state.location
          (rise-ok sunrise) (pcall hs.location.sunrise loc.latitude loc.longitude
                                   (/ context.offsetSeconds 3600) context.calendar)
          (set-ok sunset) (pcall hs.location.sunset loc.latitude loc.longitude
                                 (/ context.offsetSeconds 3600) context.calendar)
          solar {:date context.date :zone context.zone :offsetSeconds context.offsetSeconds
                 :computedAt now : sunrise : sunset}]
      (when (and rise-ok set-ok (valid-solar? solar now)) solar))))

(fn currently-dark? []
  (let [(ok success value) (pcall hs.osascript.applescript
                                "tell application \"System Events\" to tell appearance preferences to return dark mode")]
    (when (and ok success (= (type value) :boolean)) value)))

(fn run-dark-mode-hooks [?is-dark]
  (let [is-dark (if (= ?is-dark nil) (currently-dark?) ?is-dark)]
    (each [_ hook (ipairs dark-mode-hooks)] (pcall hook is-dark))))

(fn set-dark-mode [is-dark ?force]
  (when (or ?force (not= is-dark last-applied-dark))
    (if (= is-dark (currently-dark?))
        (set last-applied-dark is-dark)
        (let [(ok success) (pcall hs.osascript.applescript
                                 (.. "tell application \"System Events\" to tell appearance preferences to set dark mode to "
                                     (if is-dark "true" "false")))]
          (when (and ok success)
            (set last-applied-dark is-dark)
            (run-dark-mode-hooks is-dark))))))

(fn stop-transition []
  (set transition-id (+ transition-id 1))
  (when theme-switch-timer (theme-switch-timer:stop))
  (set theme-switch-timer nil)
  (set transition-at nil))

(fn same-day? [solar context]
  (and solar (= solar.date context.date) (= solar.zone context.zone)
       (= solar.offsetSeconds context.offsetSeconds)))

(set reconcile
     (fn [?force-appearance]
       (when (and active manual)
         (let [now (os.time) context (day-context now)
               calculated (calculate-solar context now)
               ;; Saved absolute events require today's CURRENT zone/offset too;
               ;; a noon/DST signature alone is not enough before the clock change.
               solar (or calculated
                         (and (same-day? state.solar context)
                              (= state.solar.zone (os.date "%Z" now))
                              (= state.solar.offsetSeconds (offset-seconds now))
                              state.solar))]
           (set solar-mode (if calculated :calculated solar :saved :unavailable))
           (when calculated
             (let [old state.solar]
               (set state.solar calculated)
               (when (or (not (same-day? old context))
                         (not= old.sunrise calculated.sunrise) (not= old.sunset calculated.sunset))
                 (persist))))
           (if solar
               (let [is-dark (not (and (>= now solar.sunrise) (< now solar.sunset)))
                     tomorrow (and (>= now solar.sunset) (calculate-solar (day-context now 1) now))
                     next-at (if (< now solar.sunrise) solar.sunrise
                                 (< now solar.sunset) solar.sunset
                                 tomorrow tomorrow.sunrise nil)
                     life generation]
                 (when (or (not= next-at transition-at) (not theme-switch-timer)
                           (not (theme-switch-timer:running))
                           (and next-at (> (math.abs (- (theme-switch-timer:nextTrigger) (- next-at now))) 2)))
                   (stop-transition)
                   (when (and next-at (> next-at now))
                     (let [id transition-id]
                       (set transition-at next-at)
                       (set theme-switch-timer
                            (hs.timer.doAfter (- next-at now)
                              (fn []
                                (when (and active manual (= life generation) (= id transition-id))
                                  (set theme-switch-timer nil)
                                  (set transition-at nil)
                                  (reconcile))))))))
                 (set-dark-mode is-dark ?force-appearance))
               (stop-transition))))))

(set request-refresh
     (fn [?immediate]
       (when (and active manual (not in-flight) (or ?immediate (not retry-timer)))
         (when ?immediate (stop-retry))
         (set request-id (+ request-id 1))
         (set last-attempt (monotonic))
         (set in-flight true)
         (let [life generation id request-id
               complete (fn [location err]
                          (when (and active manual (= life generation) (= id request-id) in-flight)
                            (set in-flight false)
                            (set cancel-acquisition nil)
                            (if (valid-location? location (os.time))
                                (do
                                  (stop-retry)
                                  (set failures 0)
                                  (set last-error nil)
                                  (set state.location (copy-location location))
                                  (set state.lastLiveSuccessAt (os.time))
                                  (reconcile)
                                  (when (and active manual (= life generation)) (persist)))
                                (do
                                  (set last-error
                                       (if (and (= (type err) :table)
                                                (or (= err.code :all-sources-failed) (= err.code :deadline-exceeded)))
                                           err.code :acquisition-failed))
                                  (reconcile)
                                  (when (and active manual (= life generation)) (schedule-retry))))))
               (ok cancel) (pcall locator.acquire complete)]
           (if (and ok (= (type cancel) :function))
               (when (and in-flight (= id request-id)) (set cancel-acquisition cancel))
               (complete nil nil))))))

(fn clock-signature [] (os.date "%Y-%m-%d|%Z|%z"))

(fn watchdog []
  (when (and active manual)
    (let [now (os.time) mono (monotonic) signature (clock-signature)
          changed (not= signature last-signature)
          jumped (and last-wall last-monotonic
                      (> (math.abs (- (- now last-wall) (- mono last-monotonic))) 5))
          unhealthy (or (not theme-switch-timer) (not (theme-switch-timer:running))
                        (and transition-at (>= now transition-at)))]
      (set last-wall now)
      (set last-monotonic mono)
      (set last-signature signature)
      (when (or changed jumped unhealthy) (reconcile (or changed jumped)))
      ;; A failed refresh has its own backoff; neither date nor health polls bypass it.
      (when (or changed jumped (not last-attempt) (>= (- mono last-attempt) 86400))
        (request-refresh)))))

(fn capabilities []
  (let [{:major major :minor minor} (hs.host.operatingSystemVersion)]
    (if (and (= major 10) (= minor 14)) :manual
        (or (>= major 11) (and (= major 10) (>= minor 15))) :automatic nil)))

(fn stop []
  (set active false)
  (set generation (+ generation 1))
  (set request-id (+ request-id 1))
  (when cancel-acquisition (cancel-acquisition))
  (set cancel-acquisition nil)
  (set in-flight false)
  (stop-transition)
  (stop-retry)
  (when watchdog-timer (watchdog-timer:stop))
  (set watchdog-timer nil)
  (when wake-watcher (wake-watcher:stop))
  (set wake-watcher nil)
  (when notification-watcher (notification-watcher:stop))
  (set notification-watcher nil)
  (set last-wake-at nil)
  (set last-manual-at nil)
  (set last-attempt nil)
  (set failures 0)
  (set last-applied-dark nil)
  (set manual false))

(fn start [force-manual]
  (let [cap (capabilities)]
    (assert cap)
    (when (not active)
      (set generation (+ generation 1))
      (set active true)
      (set manual (or (not (not force-manual)) (= cap :manual)))
      (let [life generation]
        ;; Install owned resources before invoking user hooks: a hook may stop
        ;; or reload the configuration synchronously during reconciliation.
        (when manual
          (set last-wall (os.time))
          (set last-monotonic (monotonic))
          (set last-signature (clock-signature))
          (set watchdog-timer (hs.timer.doEvery 60
                                (fn [] (when (= life generation) (watchdog)))))
          (set wake-watcher
               (hs.caffeinate.watcher.new
                 (fn [event]
                   (when (and active manual (= life generation)
                              (= event hs.caffeinate.watcher.systemDidWake)
                              (or (not last-wake-at) (>= (- (monotonic) last-wake-at) 2)))
                     (set last-wake-at (monotonic))
                     ;; This wake handles the wall/monotonic discontinuity now;
                     ;; don't let the next watchdog repeat the same live refresh.
                     (set last-wall (os.time))
                     (set last-monotonic (monotonic))
                     (set last-signature (clock-signature))
                     (reconcile true)
                     (when (= life generation) (request-refresh))))))
          (wake-watcher:start))
        (set notification-watcher
             (hs.distributednotifications.new
               (fn [] (when (and active (= life generation)) (run-dark-mode-hooks)))
               "AppleInterfaceThemeChangedNotification"))
        (notification-watcher:start)
        (when manual
          (load-state)
          (reconcile true)
          (when (= life generation) (request-refresh)))))))

(fn update []
  (when (and active manual)
    (reconcile true)
    (when (or (not last-manual-at) (>= (- (monotonic) last-manual-at) 2))
      (set last-manual-at (monotonic))
      (request-refresh true))))

(fn status []
  ;; Coordinates, full settings/provider records, and raw errors stay private.
  {: active : manual :source (if state.location state.location.source :none)
   :freshness (if (not state.location) :missing
                  (> (- (os.time) state.location.observedAt) stale-after) :stale :fresh)
   :solarMode solar-mode :failureCode last-error :failureCount failures :cacheError settings-error
   :inFlight in-flight :retryScheduled (not (not retry-timer))
   :retryInSeconds (and retry-at (math.max 0 (- retry-at (monotonic))))
   :transitionScheduled (not (not theme-switch-timer))})

{: start : stop :hooks dark-mode-hooks : run-dark-mode-hooks : currently-dark?
 :get-timer (fn [] theme-switch-timer) : update : status}
