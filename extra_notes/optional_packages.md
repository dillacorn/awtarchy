## 🌐 Optional Browser recommendations
You will need Firefox to use some websites and/or self-hosted web services.
```bash
sudo pacman -S firefox
```

Or install Brave via Flatpak:
```bash
flatpak install com.brave.Browser
```

## 🧰 Optional Utilities Collection

### Mouse Acceleration (raw accel alternative)
https://www.maccel.org/

---

## 📁 File Management

### TUI File Manager Suite
Modern terminal-based file management with image previews:
```bash
sudo pacman -S ueberzugpp yazi chafa
```

- **ueberzugpp** – image previews in terminal
- **yazi** – fast terminal file manager
- **chafa** – terminal graphics renderer

### Drag & Drop Utility
```bash
yay -S dragon-drop
```

Simple GUI drag-and-drop from terminal.

---

## 🔊 Audio Control
```bash
sudo pacman -S pavucontrol
```

PulseAudio Volume Control GUI.

---

## 🎵 Media

### YouTube Music Desktop Client
```bash
yay -S pear-desktop-bin
```

Unofficial YouTube Music client.

---

## 🔊 Focus Background Noise?

### Blanket Client
```bash
flatpak install com.rafaelmardojai.Blanket
```

---

## 🎥 Recording & Streaming

### OBS Studio
```bash
sudo pacman -S obs-studio
```

### GPU Screen Recorder
```bash
yay -S gpu-screen-recorder
```

### Optional AUR Recording Tools
Choose one:

**Option A** – DroidCam (Android phone as webcam):
```bash
yay -S droidcam v4l2loopback-dc-dkms obs-vkcapture
```

**Option B** – DistroAV (alternative virtual capture):
```bash
yay -S distroav obs-vkcapture
```

Usage example:
```bash
OBS_VKCAPTURE=1 gamemoderun %command%
```

---

## 🎮 Game Streaming

### Sunshine (server)
```bash
yay -S sunshine-bin
```

### Moonlight (client)
```bash
sudo pacman -S moonlight-qt
```

---

## 🔐 Authentication & VPN

### OTP client
```bash
yay -S otpclient
```

### Tailscale
```bash
sudo pacman -S tailscale
```

---

## 🎮 Gaming

### Steam
```bash
sudo pacman -S steam
```

### Flatpak gaming utilities
```bash
flatpak install flathub com.heroicgameslauncher.hgl
```

- **Heroic Games Launcher** – Epic, GOG, Amazon

### Proton Updater (ProtonPlus)
```bash
flatpak install flathub com.vysp3r.ProtonPlus
```

---

## 🗨️ VoIP & Messaging

### Discord (Vencord)
```bash
yay -S vesktop-bin
```

---

## 📦 Torrenting

### qBittorrent
```bash
sudo pacman -S qbittorrent
```

---

## 💾 System Backup

### Timeshift
```bash
sudo pacman -S timeshift
```

---

## 🖼️ GIF / Screen Capture

### Kooha
```bash
sudo pacman -S kooha
```

---

## 🧩 Remote & Local Tools
```bash
flatpak install flathub com.rustdesk.RustDesk
flatpak install flathub org.localsend.localsend_app
```

- **RustDesk** – remote desktop
- **LocalSend** – local file sharing

---

## 🎨 Multimedia Tools (Optional Bundle)
```bash
sudo pacman -S qpwgraph krita shotcut filezilla gthumb handbrake audacity
```

- **qpwgraph** – PipeWire patchbay
- **krita** – digital painting
- **shotcut** – video editor
- **filezilla** – FTP client
- **gthumb** – image viewer/manager
- **handbrake** – video transcoder
- **audacity** – audio editor
