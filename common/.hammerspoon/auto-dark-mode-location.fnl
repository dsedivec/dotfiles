;; One asynchronous acquisition only. Persistence and refresh policy live in
;; auto-dark-mode.fnl. Do not log fixes or raw provider/task errors here.
(local providers [{:source :ipinfo :url "https://ipinfo.io/json"}
                  {:source :ipwhois :url "https://ipwho.is/?fields=success,latitude,longitude"}])

(fn finite? [number]
  (and (= (type number) :number) (= number number)
       (< (math.abs number) math.huge)))

(fn coordinates? [latitude longitude]
  (and (finite? latitude) (finite? longitude)
       (<= -90 latitude 90) (<= -180 longitude 180)))

(fn native-fix? [fix]
  (and (= (type fix) :table) (coordinates? fix.latitude fix.longitude)
       (finite? fix.horizontalAccuracy) (>= fix.horizontalAccuracy 0)
       (finite? fix.timestamp)
       ;; Reject stale and implausibly future fixes; allow modest clock skew.
       (<= (- (os.time) 86400) fix.timestamp (+ (os.time) 60))))

(fn network-response [source output]
  (if (not= (type output) :string)
      (values nil nil :invalid-response)
      (> (# output) 16388)
      (values nil nil :response-too-large)
      (let [(body status-text) (string.match output "^(.*)\n(%d%d%d)$")
            status (tonumber status-text)]
        (if (not status)
            (values nil nil :invalid-response)
            (or (< status 200) (>= status 300))
            (values nil nil :http-error (if (<= 100 status 599) status nil))
            ;; hs.json.decode can log generic native parse diagnostics rather
            ;; than throw. Avoid invoking it for empty/HTML/truncated bodies.
            (not (string.match body "^%s*{.*}%s*$"))
            (values nil nil :invalid-response)
            (let [(ok response) (pcall (. (or hs.json {}) :decode) body)
                  (lat lon)
                  (if (and ok (= (type response) :table))
                      (if (= source :ipinfo)
                          (if (= (type response.loc) :string)
                              ;; IPinfo uses decimal text, not Lua hex numerals.
                              (let [(latitude longitude)
                                    (string.match response.loc "^%s*([%+%-]?%d+%.?%d*)%s*,%s*([%+%-]?%d+%.?%d*)%s*$")]
                                (values (tonumber latitude) (tonumber longitude)))
                              (values nil nil))
                          (if (= response.success true)
                              (values response.latitude response.longitude)
                              (values nil nil)))
                      (values nil nil))]
              (if (coordinates? lat lon)
                  (values lat lon nil)
                  (values nil nil :invalid-response)))))))

(fn acquire [callback]
  (var finished false)
  (var kickoff nil)
  (var watchdog nil)
  (var source-timer nil)
  (var source-generation 0)
  (var current-source :corelocation)
  (var task nil)
  (var tracker nil)
  (var tracking false)
  (var native-timer nil)
  (local failures [])
  (fn cleanup-native []
    (set tracking false)
    (when native-timer (native-timer:stop) (set native-timer nil))
    (when tracker
      (let [owned tracker]
        (set tracker nil)
        (pcall (fn [] (owned:callback nil)))
        (pcall (fn [] (owned:stopTracking))))))
  (fn cleanup-source []
    ;; Invalidate callbacks BEFORE stop/terminate, which can itself emit one.
    (set source-generation (+ source-generation 1))
    (cleanup-native)
    (when source-timer (source-timer:stop) (set source-timer nil))
    (when task
      (let [owned task]
        (set task nil)
        (pcall (fn [] (owned:terminate))))))
  (fn cleanup []
    (cleanup-source)
    (when kickoff (kickoff:stop) (set kickoff nil))
    (when watchdog (watchdog:stop) (set watchdog nil)))
  (fn cancel []
    (set finished true)
    (cleanup))
  (fn finish [location err]
    (when (not finished)
      (set finished true)
      (cleanup)
      (callback location err)))
  (fn failed [source code ?http-status]
    (table.insert failures {: source : code :httpStatus ?http-status}))
  (fn success [latitude longitude source observed-at]
    (let [retrieved-at (os.time)]
      (finish {: latitude : longitude : source :acquiredAt retrieved-at
               :observedAt (or observed-at retrieved-at)} nil)))
  (fn network [index]
    (when (not finished)
      (cleanup-source)
      (if (> index (# providers))
          (finish nil {:code :all-sources-failed : failures})
          (let [{: source : url} (. providers index)
                generation source-generation
                active? (fn [] (and (not finished) (= generation source-generation)))
                args ["-q" "--silent" "--proto" "=https" "--max-redirs" "0"
                      "--connect-timeout" "3" "--max-time" "8"
                      "--max-filesize" "16384" "--header" "Accept: application/json"
                      "--write-out" "\n%{http_code}" "--url" url]
                next-source (fn [code ?status]
                              (when (active?)
                                (cleanup-source)
                                (failed source code ?status)
                                (network (+ index 1))))
                completed (fn [exit output _stderr]
                            (when (active?)
                              ;; This task has exited; don't terminate a completed task.
                              (set task nil)
                              (if (not= exit 0)
                                  (next-source (if (= exit 28) :timeout
                                                   (= exit 63) :response-too-large
                                                   :transport-error))
                                  (let [(lat lon code status) (network-response source output)]
                                    (if code
                                        (next-source code status)
                                        (success lat lon source nil))))))]
            (set current-source source)
            (let [(created owned) (pcall (. (or hs.task {}) :new) "/usr/bin/curl" completed args)]
              (if (and created owned)
                  (do
                    (set task owned)
                    (set source-timer (hs.timer.doAfter 8 (fn [] (next-source :timeout))))
                    (let [(started result) (pcall (fn [] (owned:start)))]
                      (when (and (active?) (or (not started) (not result)))
                        ;; NSTask cannot terminate a process that never launched.
                        ;; Detach our closure; don't call private userdata disposal.
                        (pcall (fn [] (owned:setCallback nil)))
                        (set task nil)
                        (next-source :task-start-failed))))
                  (next-source :task-unavailable)))))))
  (fn track-native [location]
    (let [(created owned) (pcall location.new)
          fallback (fn [code]
                     (cleanup-native)
                     (failed :corelocation code)
                     (network 1))]
      (if (not (and created owned))
          (fallback :tracker-unavailable)
          (do
            (set tracker owned)
            (set tracking true)
            (set native-timer (hs.timer.doAfter 2 (fn [] (when tracking (fallback :timeout)))))
            (let [(ok result)
                  (pcall
                   (fn []
                     (owned:callback
                      (fn [_ message value]
                        (when (and (not finished) tracking (= tracker owned))
                          (if (= message :didUpdateLocations)
                              (when (= (type value) :table)
                                ;; Core Location puts its newest fix last.
                                (var index (# value))
                                (while (and (> index 0) tracking (not finished))
                                  (let [fix (. value index)]
                                    (when (native-fix? fix)
                                      (success fix.latitude fix.longitude :corelocation fix.timestamp)))
                                  (set index (- index 1))))
                              (= message :didFailWithError)
                              (fallback :location-error)
                              (and (= message :didChangeAuthorizationStatus) (not= value :authorized))
                              (fallback :not-authorized)))))
                     (when tracking (owned:startTracking))))]
              (when (and tracking (or (not ok) (not result)))
                (fallback :tracker-start-failed)))))))
  (fn begin []
    (let [location (or hs.location {})
          (enabled-ok enabled) (pcall location.servicesEnabled)
          (auth-ok authorization) (pcall location.authorizationStatus)]
      (if (not (and enabled-ok enabled))
          (do (failed :corelocation :services-unavailable) (network 1))
          (not (and auth-ok (= authorization :authorized)))
          (do (failed :corelocation :not-authorized) (network 1))
          (let [(ok fix) (pcall location.get)]
            (if (and ok (native-fix? fix))
                (success fix.latitude fix.longitude :corelocation fix.timestamp)
                (track-native location))))))
  (set watchdog
       (hs.timer.doAfter 20
                         (fn []
                           (when (not finished)
                             (failed current-source :deadline-exceeded)
                             (finish nil {:code :deadline-exceeded : failures})))))
  ;; Always defer, including a cached native fix, so callers can store cancel.
  (set kickoff (hs.timer.doAfter 0 (fn [] (set kickoff nil) (when (not finished) (begin)))))
  cancel)

{: acquire}
