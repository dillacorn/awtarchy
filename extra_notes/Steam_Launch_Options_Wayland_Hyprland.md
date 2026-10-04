Notes From Repo: https://github.com/dillacorn/awtarchy

### Tip: Use Glorious Egg Roll if you're having trouble with proton experimental (bleeding edge)

### These are unique launch options depending on the game and use case for [hyprland](https://github.com/hyprwm/Hyprland)

```hyprctl eval 'hl.monitor({ output = "<name>", mode = "<resolution>@<refresh_rate>", position = "<position>", scale = <scale> })'```

## Counter-Strike 2 ~ 1352x1080 4:3 stretched 240hz
```hyprctl eval 'hl.monitor({ output = "DP-2", mode = "1352x1080@240", position = "0x0", scale = 1 })'; gamemoderun %command% -novid +fps_max 0; hyprctl eval 'hl.monitor({ output = "DP-2", mode = "1920x1080@240", position = "0x0", scale = 1 })'```

## The Finals ~ 1352x1080 4:3 stretched 240hz
```hyprctl eval 'hl.monitor({ output = "DP-2", mode = "1352x1080@240", position = "0x0", scale = 1 })'; gamemoderun %command% -novid +fps_max 0 -high -dx12; hyprctl eval 'hl.monitor({ output = "DP-2", mode = "1920x1080@240", position = "0x0", scale = 1 })'```

## The Finals ~ 1680x1050 16:10 stretched 240hz
```hyprctl eval 'hl.monitor({ output = "DP-2", mode = "1680x1050@240", position = "0x0", scale = 1 })'; gamemoderun %command% -novid +fps_max 0 -high -dx12; hyprctl eval 'hl.monitor({ output = "DP-2", mode = "1920x1080@240", position = "0x0", scale = 1 })'```

### personal settings example (Zowie 400hz) + added OBS_VKCAPTURE=1 for better video capture performance OBS plugin.
```hyprctl eval 'hl.monitor({ output = "DP-1", mode = "1352x1080@400", position = "0x0", scale = 1 })'; PROTON_ENABLE_WAYLAND=1 OBS_VKCAPTURE=1 gamemoderun %command% -novid +fps_max 0 -high -dx12; hyprctl eval 'hl.monitor({ output = "DP-1", mode = "1920x1080@400", position = "0x0", scale = 1 })'```

### Using gamescope? - checkout [smtty!](https://github.com/dillacorn/smtty)


# [Lossless Scaling](https://store.steampowered.com/app/993090/Lossless_Scaling/)
# [lsfg-vk for Linux](https://github.com/PancakeTAS/lsfg-vk)

## The Finals
Launch Options:
```LSFG_PROCESS=TheFinals gamemoderun %command% -novid +fps_max 0 -high -dx12```

lsfg-vk conf.toml
```
[[game]] # override The Finals
exe = "TheFinals"

multiplier = 2
performance_mode = true
experimental_present_mode = "mailbox"
```
cap frame rate to a consistantly achieved value.. for me that's 120fps unfortunantly and I hate how this game preforms but it's a good example.

Ideally I won't be using lossless scaling for this title.

## Elden Ring
(60fps lock multiplied by 4 = 240 fps)

lsfg-vk conf.toml
```
[[game]] # override Elden Ring Nightreign
exe = "nightreign"

multiplier = 4
performance_mode = false
```
