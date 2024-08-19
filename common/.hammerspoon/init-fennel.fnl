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
                                 {:depth 3})
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


;;; Moom replacements

(global moom-modal (hs.hotkey.modal.new "alt" "escape"))
(global moom-modal-alert nil)
(global moom-modal-saved-frames {})

(fn moom-modal-window-key [win]
  "Make unique key for window WIN."
  (.. (or (-?> (win:application) (: :pid)) "nil app")
      "|"
      (or (win:id) "nil win")))

(fn moom-modal-save-frame [?win ?key ?frame]
  "Save the geometry of WIN."
  (let [win (or ?win (hs.window.frontmostWindow))
        key (or ?key (moom-modal-window-key win))
        frame (or ?frame (win:frame))]
    (tset moom-modal-saved-frames key (hs.geometry.copy frame))))

(fn moom-modal-maybe-save-frame [?win ?frame]
  "Save the geometry of WIN if it hasn't been saved previously."
  (let [win (or ?win (hs.window.frontmostWindow))
        key (moom-modal-window-key win)]
    (when (not (. moom-modal-saved-frames key))
      (moom-modal-save-frame win key ?frame))))

(fn moom-modal-restore-frame [?win]
  "Restore previously saved geometry of WIN, if any.

If the geometry was saved, it is cleared before restoring the window's
geometry."
  (let [win (or ?win (hs.window.frontmostWindow))
        key (moom-modal-window-key win)
        frame (. moom-modal-saved-frames key)]
    (when frame
      (tset moom-modal-saved-frames key nil)
      (win:setFrame frame 0))))

(fn moom-modal-clear-alert []
  "Clear the Moom overlay, if any."
  (when moom-modal-alert
    (hs.alert.closeSpecific moom-modal-alert)
    (global moom-modal-alert nil)))

(fn moom-modal-show-alert [msg]
  "Show the Moom overlay."
  (moom-modal-clear-alert)
  (global moom-modal-alert
          (hs.alert.show msg
                         {:fadeInDuration 0
                          :padding 75
                          :fillColor {:white 0 :alpha 0.5}}
                         "indefinite")))

(fn moom-modal.entered []
  (moom-modal-show-alert "Moom"))

(fn moom-modal.exited []
  (moom-modal-clear-alert))

(fn moom-window-center []
  "Center the frontmost window."
  (: (hs.window.frontmostWindow) :centerOnScreen nil true 0))

(fn moom-window-grow [axis]
  (let [win (hs.window.frontmostWindow)
        win-frame (win:frame)
        screen-frame (: (win:screen) :frame)
        axis2 (if (= axis :x) :x2 :y2)]
    (moom-modal-maybe-save-frame win win-frame)
    (tset win-frame axis (. screen-frame axis))
    (tset win-frame axis2 (. screen-frame axis2))
    (win:setFrameInScreenBounds win-frame 0)))

(fn moom-window-to-left-side []
  (let [win (hs.window.frontmostWindow)
        frame (win:frame)]
    (moom-modal-maybe-save-frame win frame)
    (tset frame :x 0)
    (win:setFrameInScreenBounds frame 0)))

(fn moom-window-to-right-side []
  (let [win (hs.window.frontmostWindow)
        frame (win:frame)]
    (moom-modal-maybe-save-frame win frame)
    (tset frame :x (- (. (: (win:screen) :frame) :x2) (. frame :w)))
    (win:setFrameInScreenBounds frame 0)))

(fn moom-window-to-top-side []
  (let [win (hs.window.frontmostWindow)
        frame (win:frame)]
    (moom-modal-maybe-save-frame win frame)
    (tset frame :y (. (: (win:screen) :frame) :y))
    (win:setFrameInScreenBounds frame 0)))

(fn moom-window-to-bottom-side []
  (let [win (hs.window.frontmostWindow)
        frame (win:frame)]
    (moom-modal-maybe-save-frame win frame)
    (tset frame :y (- (. (: (win:screen) :frame) :y2) (. frame :h)))
    (win:setFrameInScreenBounds frame 0)))

(fn moom-window-move [axis amount]
  (let [win (hs.window.frontmostWindow)
        frame (win:frame)]
    (tset frame axis (+ (. frame axis) amount))
    (win:setFrame frame 0)))

(fn moom-window-resize [dimension amount]
  (let [win (hs.window.frontmostWindow)
        frame (win:frame)]
    (tset frame dimension (+ (. frame dimension) amount))
    (win:setFrame frame 0)))

(fn moom-window-set-unit-frame [unit-rect]
  "Move the frontmost window based on the given unit rectangle.

See hs.geometry documentation for the syntax of UNIT-RECT."
  (let [win (hs.window.frontmostWindow)]
    (moom-modal-maybe-save-frame win)
    (: win :move unit-rect nil true 0)))

(fn moom-window-maximize [?win]
  (let [ax-win (hs.axuielement.windowElement
                (or ?win (hs.window.frontmostWindow)))]
    (ax-win:elementSearch (fn [_msg [ax-button & _]]
                            (when ax-button
                              (ax-button:performAction "AXZoomWindow")))
                          (hs.axuielement.searchCriteriaFunction
                           {:attribute "AXSubrole" :value "AXFullScreenButton"})
                          {:count 1})))

(moom-modal:bind "" "escape" (fn [] (moom-modal:exit)))
(moom-modal:bind "alt" "escape" (fn [] (moom-modal:exit)))
(moom-modal:bind "" "return" (fn [] (moom-modal:exit)))
(moom-modal:bind "" "tab" moom-window-center)
(moom-modal:bind "" "g" #(moom-window-grow :y))
(moom-modal:bind "shift" "g" #(moom-window-grow :x))
(moom-modal:bind "" "[" moom-window-to-left-side)
(moom-modal:bind "" "]" moom-window-to-right-side)
(moom-modal:bind ""  "u" moom-window-to-top-side)
(moom-modal:bind ""  "d" moom-window-to-bottom-side)
(moom-modal:bind "shift" "[" #(moom-window-set-unit-frame "[0, 0, 50, 100]"))
(moom-modal:bind "shift" "]" #(moom-window-set-unit-frame "[50, 0, 100, 100]"))
(moom-modal:bind "shift" "u" #(moom-window-set-unit-frame "[0, 0, 100, 50]"))
(moom-modal:bind "shift" "d" #(moom-window-set-unit-frame "[0, 50, 100, 100]"))
(each [_ dir (ipairs [["up" :y -1]
                      ["down" :y 1]
                      ["left" :x -1]
                      ["right" :x 1]])]
  (let [[key axis amount] dir
        dimension (if (= axis :x) :w :h)
        move-fn #(moom-window-move axis (* amount 100))
        resize-fn #(moom-window-resize dimension (* amount 100))]
    (moom-modal:bind [] key move-fn nil move-fn)
    (moom-modal:bind ["shift"] key resize-fn nil resize-fn)))
(moom-modal:bind "" "r" moom-modal-restore-frame)
(moom-modal:bind "" "s" moom-modal-save-frame)

(hs.hotkey.bind ["alt"] "=" moom-window-maximize)


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
