;;; Utilities

(lambda get-iterm2-cookie []
  (let [(_ result _) (hs.osascript.applescript
                      "tell application \"iTerm2\" to request cookie")]
    result))

(lambda execve-background [prog args extra-env]
  (let [task (hs.task.new prog
                          (lambda [rc out err]
                            (print (.. prog " exited " rc))
                            (when (not= rc 0)
                              (print (.. "out: " out))
                              (print (.. "err: " err))))
                          (fn [] false)
                          args)]
    (when extra-env
      (let [full-env (task:environment)]
        (each [name val (pairs extra-env)]
          (tset full-env name val))
        (task:setEnvironment full-env)))
    (task:start)
    task))


;;; Automatic dark mode switching

(local hs-themed-console-colors
       {
        ;; The light colors here are Hammerspoon's defaults.
        :light {:consoleCommandColor   {:white 0}
                :consolePrintColor     {:red 0.6 :blue 0.432 :green 0}
                :consoleResultColor    {:red 0 :blue 0.7 :green 0.532}
                :outputBackgroundColor {:white 1}}
        ;; I came up with these colors myself.  Tested WCAG AAA
        ;; contrast ratio at least 7:1.
        :dark {:consoleCommandColor   {:white 1}
               :consolePrintColor     {:hex "#ff47cb"}
               :consoleResultColor    {:hex "#00a1d0"}
               :outputBackgroundColor {:white 0}}
        })

(lambda set-hs-console-theme [is-dark]
  (hs.console.darkMode is-dark)
  (each [func color (pairs (. hs-themed-console-colors
                              (if is-dark :dark :light)))]
    ((. hs.console func) color)))

(lambda my-dark-mode-hook [is-dark]
  (print "my-dark-mode-hook running")
  (os.execute (.. hs.configdir "/update_macos_theme.sh"))
  (set-hs-console-theme is-dark)
  (print "my-dark-mode-hook finished"))

(local auto-dark-mode (require :auto-dark-mode))

(table.insert auto-dark-mode.hooks my-dark-mode-hook)

(auto-dark-mode.start)

;; Call my hook to sync up with current system state.
(my-dark-mode-hook (auto-dark-mode.currently-dark?))


;;; "Key macros"

(global key-macro-log (hs.logger.new "my-key-macros"))

(lambda my-send-keys [keys ?app]
  (let [app (and ?app (hs.application.get ?app))]
    (assert (or (not ?app) app))
    (each [_ spec (ipairs keys)]
      (let [[mods char] (if (= (type spec) "string")
                            [[] spec]
                            spec)]
        (hs.eventtap.keyStroke mods char 50000 app)))))

(lambda mail-focus-frontmost-window-message-body [?callback]
  (key-macro-log.d "Attempting to focus Mail message body")
  (let [front-win (-?> (hs.application.get "com.apple.mail")
                       (: :visibleWindows)
                       (. 1)
                       (hs.axuielement.windowElement))]
    (if front-win
        (front-win:elementSearch (fn [_msg [first-elem & other-elems]]
                                   (key-macro-log.d "mail body search"
                                                    _msg first-elem)
                                   (when first-elem
                                     (first-elem:setAttributeValue
                                      hs.axuielement.attributes.focused
                                      true)
                                     (key-macro-log.d "set it to focused"))
                                   (and ?callback (?callback first-elem)))
                                 ;; We really care about the AXWebArea, but
                                 ;; this one is a direct child of the
                                 ;; window, and lets us use depth=1,
                                 ;; which speeds up the search a
                                 ;; *ton*.
                                 (hs.axuielement.searchCriteriaFunction
                                  "AXScrollArea")
                                 {:depth 1})
        (key-macro-log.w "Could not find front-most window for Mail"))))

(global mail-quotefix-hotkey
        (hs.hotkey.new ["ctrl" "alt"] "f" nil
                       (fn []
                         (mail-focus-frontmost-window-message-body
                          (fn [focused]
                            (when focused
                              (my-send-keys [[["cmd"] "up"]
                                             "down"
                                             "down"
                                             [["alt"] "right"]
                                             [["cmd" "alt"] "'"]
                                             [["cmd"] "up"]]
                                            "com.apple.mail")))))))

(global mail-hotkeys [mail-quotefix-hotkey])

(global mail-win-watcher  (hs.window.filter.new "Mail"))

(each [event method (pairs {hs.window.filter.windowFocused :enable
                            hs.window.filter.windowUnfocused :disable})]
  (mail-win-watcher:subscribe event (let [method method]
                                      (fn [_win _name _event]
                                        (each [_ hotkey (ipairs mail-hotkeys)]
                                          (: hotkey method))))))


;;; Jeejah REPL

;; (set package.path (.. package.path ";" HS_LUA_ROOT "/src/jeejah/?.lua"))
;; (local jeejah (require "jeejah"))
;; (global jeejah-coro (jeejah.start))
;; (global jeejah-coro-freq 0.01)
;; (fn jeejah-spin []
;;   (coroutine.resume jeejah-coro)
;;   (when (not= (coroutine.status jeejah-coro)
;;               "dead")
;;     (hs.timer.doAfter jeejah-coro-freq jeejah-spin)))
;; (global jeejah-timer (hs.timer.doAfter jeejah-coro-freq jeejah-spin))


{: my-dark-mode-hook
 :adm auto-dark-mode
 :send-keys my-send-keys
 : mail-win-watcher
 : mail-hotkeys
 : key-macro-log}
