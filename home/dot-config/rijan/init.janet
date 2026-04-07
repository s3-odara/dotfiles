(array/push
  (config :xkb-bindings)
  [:Return {:mod4 true :shift true} (action/spawn ["foot"])]
  [:s {:mod4 true} (action/spawn ["fuzzel"])]
  [:m {:mod4 true} (action/spawn ["/home/odara/.local/bin/lock"])]
  [:r {:mod4 true} (action/spawn ["/home/odara/.local/bin/lock-and-suspend"])]
  [:Escape {:mod4 true} (action/exit-session)]

  [:q {:mod4 true} (action/close)]
  [:f {:mod4 true} (action/fullscreen)]
  [:space {:mod4 true} (action/float)]

  [:h {:mod4 true} (action/focus :prev)]
  [:l {:mod4 true} (action/focus :next)]

  [:comma {:mod4 true} (action/focus-output)]
  [:period {:mod4 true} (action/focus-output)]
  [:Left {:mod4 true} (action/focus-output)]
  [:Right {:mod4 true} (action/focus-output)]
  [:Up {:mod4 true} (action/focus-output)]
  [:Down {:mod4 true} (action/focus-output)]

  [:p {:mod4 true} (action/spawn ["/home/odara/.local/bin/screenshot-copy"])]
  [:p {:mod4 true :shift true} (action/spawn ["/home/odara/.local/bin/screenshot-save"])]

  [:v {:mod4 true} (action/spawn ["playerctl" "play-pause"])]
  [:c {:mod4 true} (action/spawn ["playerctl" "previous"])]
  [:b {:mod4 true} (action/spawn ["playerctl" "next"])]

  [:XF86AudioRaiseVolume {} (action/spawn ["/home/odara/.local/bin/wob-volume" "5%+"])]
  [:XF86AudioLowerVolume {} (action/spawn ["/home/odara/.local/bin/wob-volume" "5%-"])]
  [:XF86AudioMute {} (action/spawn ["wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"])]
  [:XF86AudioMicMute {} (action/spawn ["wpctl" "set-mute" "@DEFAULT_AUDIO_SOURCE@" "toggle"])]
  [:XF86MonBrightnessUp {} (action/spawn ["/home/odara/.local/bin/brightness-wob" "+5%"])]
  [:XF86MonBrightnessDown {} (action/spawn ["/home/odara/.local/bin/brightness-wob" "5%-"])])

(for i 1 10
  (def keysym (keyword i))
  (array/push
    (config :xkb-bindings)
    [keysym {:mod4 true} (action/focus-tag i)]
    [keysym {:mod4 true :shift true} (action/set-tag i)]))

(array/push
  (config :pointer-bindings)
  [:left {:mod4 true} (action/pointer-move)]
  [:right {:mod4 true} (action/pointer-resize)])

(defn action/move [dir]
  (fn [seat binding]
    (when-let [focused (seat :focused)]
      (unless (focused :float)
        (when-let [target (action/target seat
                                         (case dir
                                           :left :prev
                                           :right :next
                                           (error "invalid dir")))
                   fi (index-of focused (wm :windows))
                   ti (index-of target (wm :windows))]
          (put (wm :windows) fi target)
          (put (wm :windows) ti focused)
          (seat/focus seat focused))))))
(array/push
  (config :xkb-bindings)
  [:h {:mod4 true :shift true} (action/move :left)]
  [:l {:mod4 true :shift true} (action/move :right)])

(defn output/adjacent [output dir]
  (var best nil)
  (var best-dist nil)
  (each other (wm :outputs)
    (unless (= other output)
      (def dx (- (other :x) (output :x)))
      (when (case dir
              :left (< dx 0)
              :right (> dx 0)
              false)
        (def dist (case dir
                    :left (- dx)
                    :right dx
                    0))
        (when (or (not best) (< dist best-dist))
          (set best other)
          (set best-dist dist)))))
  best)

(defn action/send-output [dir]
  (fn [seat binding]
    (when-let [window (seat :focused)
               current-output (or (window/tag-output window)
                                  (seat :focused-output))
               target-output (output/adjacent current-output dir)
               target-tag (min-of (keys (target-output :tags)))]
      (put window :tag target-tag)
      (seat/focus-output seat target-output)
      (seat/focus seat window))))

(array/push
  (config :xkb-bindings)
  [:Left {:mod4 true :shift true} (action/send-output :left)]
  [:Right {:mod4 true :shift true} (action/send-output :right)]
  [:comma {:mod4 true :shift true} (action/send-output :left)]
  [:period {:mod4 true :shift true} (action/send-output :right)])
