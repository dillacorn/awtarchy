Arch now packages `noise-suppression-for-voice` in `extra`, and the LADSPA plugin installs to `/usr/lib/ladspa/librnnoise_ladspa.so`. That is the safer Arch path and avoids the stale home-directory plugin copy that broke your audio. Upstream still documents the PipeWire `filter-chain` approach, so this keeps the same method but uses the packaged system plugin path instead. ([Arch Linux][1])

## Directions from Werman
#### [Werman's README - PipeWire Instructions](https://github.com/werman/noise-suppression-for-voice?tab=readme-ov-file#pipewire)

---

## My Instructions (Using Terminal)
### Arch Linux Recommended Method

This version is safer on Arch because it uses the packaged plugin from the Arch repo instead of copying a downloaded `.so` into `~/.config/pipewire`.

---

# 1. Install the Plugin from the Arch Repo
```sh
sudo pacman -S noise-suppression-for-voice
````

# 2. Create the PipeWire Configuration Directory

```sh
mkdir -p ~/.config/pipewire/pipewire.conf.d
```

# 3. If You Previously Used My Old Guide, Remove the Old Local Plugin Copy

```sh
rm -f ~/.config/pipewire/librnnoise_ladspa.so
```

# 4. Create and Edit `99-input-denoising.conf`

```sh
nano ~/.config/pipewire/pipewire.conf.d/99-input-denoising.conf
```

# 5. Paste the Following Configuration into `99-input-denoising.conf`

# **Notice!** - This uses the Arch-installed system plugin path. No username editing needed.

```ini
context.modules = [
{   name = libpipewire-module-filter-chain
    args = {
        node.description =  "Noise Canceling source"
        media.name =  "Noise Canceling source"
        filter.graph = {
            nodes = [
                {
                    type = ladspa
                    name = rnnoise
                    plugin = /usr/lib/ladspa/librnnoise_ladspa.so
                    label = noise_suppressor_mono
                    control = {
                        "VAD Threshold (%)" = 50.0
                        "VAD Grace Period (ms)" = 200
                        "Retroactive VAD Grace (ms)" = 0
                    }
                }
            ]
        }
        capture.props = {
            node.name =  "capture.rnnoise_source"
            node.passive = true
            audio.rate = 48000
        }
        playback.props = {
            node.name =  "rnnoise_source"
            media.class = Audio/Source
            audio.rate = 48000
        }
    }
}
]
```

# 6. Reload and Restart User Audio Services

# **Ensure the config is correct before running this.**

```sh
systemctl --user daemon-reload
systemctl --user reset-failed
systemctl --user restart pipewire.service wireplumber.service pipewire-pulse.service
```

# 7. Verify PipeWire Is Still Running

```sh
wpctl status
pactl info
```

# 8. Select the New Input Device

Choose `Noise Canceling source` as your microphone input in Discord, OBS, browser apps, or other audio software.

![noise\_suppression](https://raw.githubusercontent.com/dillacorn/arch-hypr-dots/refs/heads/main/extra_notes/screenshots_for_guides/werman_noise_suppression/noise_suppression.png)

# done, enjoy!

[1]: https://archlinux.org/packages/extra/x86_64/noise-suppression-for-voice/ "Arch Linux - noise-suppression-for-voice 1.10-1 (x86_64)"
