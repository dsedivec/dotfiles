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
