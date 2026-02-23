#!/usr/bin/env python3
from __future__ import annotations

# github.com/dillacorn/awtarchy/tree/main/config/hypr/scripts
# ~/.config/hypr/scripts/wallpicker.py
#
# Minimal dark wallpaper picker for Hyprland
# - Visual thumbnail grid from ~/Pictures/wallpapers (recursive)
# - Bottom options bar (minimal / waytrogen-like layout)
# - Backend selector: swww or hyprpaper
# - Per-display or all displays
# - Random button
# - Stable Wayland app_id/class: "wallpicker" (for Hyprland window rules)
# - Auto-creates ~/.local/share/applications/wallpicker.desktop to avoid portal warning
#
# Arch deps (typical):
#   sudo pacman -S pyside6 python python-pillow swww hyprland hyprpaper

import hashlib
import json
import random
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from PIL import Image, ImageOps

from PySide6.QtCore import Qt, QSize, QTimer
from PySide6.QtGui import QAction, QColor, QFont, QIcon, QPainter, QPen, QPixmap
from PySide6.QtWidgets import (
    QApplication,
    QCheckBox,
    QComboBox,
    QFileDialog,
    QFrame,
    QHBoxLayout,
    QLabel,
    QLineEdit,
    QListWidget,
    QListWidgetItem,
    QMainWindow,
    QMessageBox,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

APP_NAME = "wallpicker"
APP_ID = "wallpicker"

DEFAULT_DIR = Path.home() / "Pictures" / "wallpapers"
CACHE_DIR = Path.home() / ".cache" / "wallpicker" / "thumbs"
DESKTOP_FILE = Path.home() / ".local" / "share" / "applications" / f"{APP_ID}.desktop"

THUMB_W = 240
THUMB_H = 150
ICON_SIZE = QSize(THUMB_W, THUMB_H)
GRID_SIZE = QSize(248, 198)
THUMB_STYLE_VERSION = "contain-center-v2-delegate"  # keep to reuse existing cache

SUPPORTED_EXTS = {
    ".jpg", ".jpeg", ".png", ".webp", ".bmp", ".gif", ".tif", ".tiff", ".avif", ".jxl"
}
ALL_DISPLAYS = "All displays"

DEFAULTS = {
    "backend": "swww",
    "swww_resize": "crop",
    "swww_transition_type": "fade",
    "swww_transition_duration": "3.0",
    "swww_transition_fps": "30",
    "swww_filter": "Lanczos3",
    "hyprpaper_mode": "cover",
}


@dataclass(frozen=True)
class WallItem:
    path: Path
    thumb_path: Path
    mtime_ns: int
    size_bytes: int


def run_cmd(cmd: list[str], timeout: float = 3.0) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, text=True, capture_output=True, check=False, timeout=timeout)


def ensure_local_desktop_file(script_path: Path) -> None:
    """
    Create/update a matching desktop entry so Qt portal registration for app_id 'wallpicker'
    does not warn: 'App info not found for wallpicker'
    """
    DESKTOP_FILE.parent.mkdir(parents=True, exist_ok=True)

    if not script_path.exists():
        return

    content = "\n".join(
        [
            "[Desktop Entry]",
            "Version=1.0",
            "Type=Application",
            f"Name={APP_NAME}",
            "Comment=Minimal wallpaper picker for Hyprland",
            f"Exec={script_path}",
            "Icon=preferences-desktop-wallpaper",
            "Terminal=false",
            "Categories=Utility;Graphics;",
            "StartupNotify=true",
            "",
        ]
    )

    try:
        current = DESKTOP_FILE.read_text(encoding="utf-8") if DESKTOP_FILE.exists() else ""
        if current != content:
            DESKTOP_FILE.write_text(content, encoding="utf-8")
            try:
                DESKTOP_FILE.chmod(0o644)
            except Exception:
                pass
    except Exception:
        # Non-fatal. App can still run; worst case portal warning remains.
        pass


def make_thumb_cache_path(path: Path, mtime_ns: int, size_bytes: int) -> Path:
    h = hashlib.sha256()
    h.update(str(path).encode("utf-8", errors="ignore"))
    h.update(b"\0")
    h.update(str(mtime_ns).encode())
    h.update(b"\0")
    h.update(str(size_bytes).encode())
    h.update(b"\0")
    h.update(f"{THUMB_W}x{THUMB_H}".encode())
    h.update(b"\0")
    h.update(THUMB_STYLE_VERSION.encode())
    return CACHE_DIR / f"{h.hexdigest()}.jpg"


def ensure_thumb(item: WallItem) -> None:
    """
    Create a centered, letterboxed thumbnail (contain + center).
    Cached to disk so subsequent launches are fast.
    """
    if item.thumb_path.exists():
        return

    item.thumb_path.parent.mkdir(parents=True, exist_ok=True)

    try:
        with Image.open(item.path) as im:
            im = ImageOps.exif_transpose(im)
            if im.mode != "RGB":
                im = im.convert("RGB")

            contained = ImageOps.contain(im, (THUMB_W, THUMB_H), method=Image.Resampling.LANCZOS)
            canvas = Image.new("RGB", (THUMB_W, THUMB_H), (0, 0, 0))
            x = (THUMB_W - contained.width) // 2
            y = (THUMB_H - contained.height) // 2
            canvas.paste(contained, (x, y))
            canvas.save(item.thumb_path, "JPEG", quality=88, optimize=True)
    except Exception:
        Image.new("RGB", (THUMB_W, THUMB_H), (0, 0, 0)).save(
            item.thumb_path, "JPEG", quality=80, optimize=True
        )


def placeholder_pixmap(size: QSize, text: str = "Loading") -> QPixmap:
    pm = QPixmap(size)
    pm.fill(QColor("#000000"))
    p = QPainter(pm)
    p.setPen(QPen(QColor("#262626"), 2))
    p.drawRect(1, 1, size.width() - 2, size.height() - 2)
    p.drawLine(0, 0, size.width(), size.height())
    p.drawLine(size.width(), 0, 0, size.height())
    p.setPen(QColor("#bfbfbf"))
    p.drawText(pm.rect(), Qt.AlignmentFlag.AlignCenter, text)
    p.end()
    return pm


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        CACHE_DIR.mkdir(parents=True, exist_ok=True)

        self.items: list[WallItem] = []
        self.filtered: list[WallItem] = []
        self.path_to_item: dict[Path, WallItem] = {}
        self.path_to_widget: dict[Path, QListWidgetItem] = {}
        self.pending: list[WallItem] = []

        self.thumb_timer = QTimer(self)
        self.thumb_timer.timeout.connect(self._thumb_tick)

        self._build_ui()
        self._theme()
        self.refresh_displays()
        self.scan()

    def _build_ui(self) -> None:
        self.setWindowTitle(APP_NAME)
        self.resize(1320, 840)
        self.setMinimumSize(920, 640)

        root = QWidget()
        self.setCentralWidget(root)

        v = QVBoxLayout(root)
        v.setContentsMargins(8, 8, 8, 8)
        v.setSpacing(8)

        self.grid = QListWidget()
        self.grid.setViewMode(QListWidget.ViewMode.IconMode)
        self.grid.setIconSize(ICON_SIZE)
        self.grid.setGridSize(GRID_SIZE)
        self.grid.setResizeMode(QListWidget.ResizeMode.Adjust)
        self.grid.setMovement(QListWidget.Movement.Static)
        self.grid.setWrapping(True)
        self.grid.setWordWrap(True)
        self.grid.setSpacing(8)
        self.grid.setSelectionMode(QListWidget.SelectionMode.SingleSelection)
        self.grid.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        self.grid.setUniformItemSizes(True)
        # Batch layout reduces initial population cost on large wallpaper sets
        self.grid.setLayoutMode(QListWidget.LayoutMode.Batched)
        self.grid.setBatchSize(128)
        v.addWidget(self.grid, 1)

        bottom = QFrame()
        bottom.setObjectName("BottomPanel")
        bv = QVBoxLayout(bottom)
        bv.setContentsMargins(8, 8, 8, 8)
        bv.setSpacing(6)

        # Row 1: folder + search
        row1 = QHBoxLayout()
        self.folder_edit = QLineEdit(str(DEFAULT_DIR))
        self.search_edit = QLineEdit()
        self.search_edit.setPlaceholderText("Search")
        self.recursive_check = QCheckBox("Recursive")
        self.recursive_check.setChecked(True)
        btn_folder = QPushButton("Folder")
        btn_rescan = QPushButton("Rescan")

        row1.addWidget(QLabel("Dir"))
        row1.addWidget(self.folder_edit, 1)
        row1.addWidget(btn_folder)
        row1.addWidget(btn_rescan)
        row1.addWidget(self.recursive_check)
        row1.addWidget(QLabel("Find"))
        row1.addWidget(self.search_edit, 1)
        bv.addLayout(row1)

        # Row 2: options / actions
        row2 = QHBoxLayout()

        self.backend_combo = QComboBox()
        self.backend_combo.addItems(["swww", "hyprpaper"])
        self.backend_combo.setCurrentText(DEFAULTS["backend"])

        self.display_combo = QComboBox()
        self.display_combo.setMinimumWidth(180)

        self.resize_combo = QComboBox()
        self.resize_combo.addItems(["crop", "fit", "stretch", "no"])
        self.resize_combo.setCurrentText(DEFAULTS["swww_resize"])

        self.transition_combo = QComboBox()
        self.transition_combo.addItems(
            ["fade", "simple", "grow", "center", "any", "wipe", "wave", "outer", "random", "none"]
        )
        self.transition_combo.setCurrentText(DEFAULTS["swww_transition_type"])

        self.duration_edit = QLineEdit(DEFAULTS["swww_transition_duration"])
        self.duration_edit.setFixedWidth(64)

        self.fps_edit = QLineEdit(DEFAULTS["swww_transition_fps"])
        self.fps_edit.setFixedWidth(54)

        self.filter_combo = QComboBox()
        self.filter_combo.addItems(["Lanczos3", "Mitchell", "CatmullRom", "Bilinear", "Nearest"])
        self.filter_combo.setCurrentText(DEFAULTS["swww_filter"])

        self.hyprpaper_mode_label = QLabel("Hypr Mode")
        self.hyprpaper_mode_combo = QComboBox()
        self.hyprpaper_mode_combo.addItems(["cover", "contain", "fill", "tile"])
        self.hyprpaper_mode_combo.setCurrentText(DEFAULTS["hyprpaper_mode"])

        self.btn_apply = QPushButton("Apply")
        self.btn_apply.setEnabled(False)
        btn_random = QPushButton("Random")
        btn_open = QPushButton("Open Dir")

        row2.addWidget(QLabel("Backend"))
        row2.addWidget(self.backend_combo)
        row2.addWidget(QLabel("Display"))
        row2.addWidget(self.display_combo)

        row2.addWidget(QLabel("Resize"))
        row2.addWidget(self.resize_combo)

        row2.addWidget(QLabel("Transition"))
        row2.addWidget(self.transition_combo)

        row2.addWidget(QLabel("Dur"))
        row2.addWidget(self.duration_edit)

        row2.addWidget(QLabel("FPS"))
        row2.addWidget(self.fps_edit)

        row2.addWidget(QLabel("Filter"))
        row2.addWidget(self.filter_combo)

        row2.addWidget(self.hyprpaper_mode_label)
        row2.addWidget(self.hyprpaper_mode_combo)

        row2.addStretch(1)
        row2.addWidget(btn_open)
        row2.addWidget(btn_random)
        row2.addWidget(self.btn_apply)

        bv.addLayout(row2)

        # Row 3: status
        row3 = QHBoxLayout()
        self.selection_label = QLabel("No selection")
        self.status_label = QLabel("Ready")
        self.selection_label.setObjectName("Subtle")
        self.status_label.setObjectName("Subtle")
        row3.addWidget(self.selection_label, 3)
        row3.addWidget(self.status_label, 2)
        bv.addLayout(row3)

        v.addWidget(bottom)

        # Signals
        btn_folder.clicked.connect(self.pick_folder)
        btn_rescan.clicked.connect(self.scan)
        self.recursive_check.toggled.connect(self.scan)
        self.search_edit.textChanged.connect(self.apply_filter)
        btn_open.clicked.connect(self.open_dir)
        btn_random.clicked.connect(self.apply_random)
        self.btn_apply.clicked.connect(self.apply_selected)
        self.backend_combo.currentTextChanged.connect(self.on_backend_changed)

        self.grid.currentItemChanged.connect(self.on_selection_changed)
        self.grid.itemDoubleClicked.connect(lambda _i: self.apply_selected())

        # Shortcuts
        a_refresh = QAction(self)
        a_refresh.setShortcut("F5")
        a_refresh.triggered.connect(self.scan)
        self.addAction(a_refresh)

        a_apply = QAction(self)
        a_apply.setShortcut("Return")
        a_apply.triggered.connect(self.apply_selected)
        self.addAction(a_apply)

        a_random = QAction(self)
        a_random.setShortcut("Ctrl+R")
        a_random.triggered.connect(self.apply_random)
        self.addAction(a_random)

        self.on_backend_changed(self.backend_combo.currentText())

    def _theme(self) -> None:
        font = QFont("NotoSansM Nerd Font Mono")
        if not font.exactMatch():
            font = QFont("JetBrainsMono Nerd Font")
        if not font.exactMatch():
            font = QFont("monospace")
        font.setPointSize(10)
        self.setFont(font)

        self.setStyleSheet("""
        QWidget {
            background: #000000;
            color: #e6e6e6;
        }
        QListWidget {
            background: #000000;
            border: 1px solid #1a1a1a;
            border-radius: 8px;
            selection-background-color: #0f0f0f;
            selection-color: #ffffff;
            outline: none;
        }
        QListWidget::item {
            background: #050505;
            border: 1px solid #181818;
            border-radius: 6px;
            margin: 2px;
            padding: 4px;
        }
        QListWidget::item:selected {
            border: 1px solid #6a6a6a;
            background: #101010;
        }
        QFrame#BottomPanel {
            background: #030303;
            border: 1px solid #1a1a1a;
            border-radius: 8px;
        }
        QLineEdit, QComboBox {
            background: #050505;
            border: 1px solid #242424;
            border-radius: 6px;
            padding: 5px 7px;
            color: #e6e6e6;
            selection-background-color: #1a1a1a;
            selection-color: #ffffff;
        }
        QComboBox::drop-down { border: none; width: 18px; }
        QPushButton {
            background: #080808;
            border: 1px solid #2a2a2a;
            border-radius: 6px;
            padding: 6px 10px;
            color: #e6e6e6;
        }
        QPushButton:hover { background: #101010; border-color: #3a3a3a; }
        QPushButton:pressed { background: #151515; }
        QPushButton:disabled { background: #050505; color: #7a7a7a; border-color: #1d1d1d; }
        QLabel#Subtle { color: #a0a0a0; }
        QCheckBox { spacing: 8px; color: #dcdcdc; }
        QCheckBox::indicator { width: 14px; height: 14px; }
        QCheckBox::indicator:unchecked { border: 1px solid #4a4a4a; background: #050505; }
        QCheckBox::indicator:checked { border: 1px solid #7a7a7a; background: #222222; }
        QScrollBar:vertical { background:#000000; width:12px; margin:2px; border-radius:6px; }
        QScrollBar::handle:vertical { background:#222222; min-height:24px; border-radius:6px; }
        QScrollBar::handle:vertical:hover { background:#303030; }
        QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height:0px; }
        QToolTip { background:#050505; color:#e6e6e6; border:1px solid #2a2a2a; }
        """)

    def status(self, msg: str) -> None:
        self.status_label.setText(msg)
        # Keep UI responsive during large scans/thumb generation
        QApplication.processEvents()

    def on_backend_changed(self, backend: str) -> None:
        use_swww = backend == "swww"

        # swww-only controls
        self.resize_combo.setEnabled(use_swww)
        self.transition_combo.setEnabled(use_swww)
        self.duration_edit.setEnabled(use_swww)
        self.fps_edit.setEnabled(use_swww)
        self.filter_combo.setEnabled(use_swww)

        # hyprpaper-only mode control
        self.hyprpaper_mode_label.setVisible(not use_swww)
        self.hyprpaper_mode_combo.setVisible(not use_swww)
        self.hyprpaper_mode_combo.setEnabled(not use_swww)

        self.status("Backend: swww" if use_swww else "Backend: hyprpaper (transitions disabled)")

    def pick_folder(self) -> None:
        current = str(Path(self.folder_edit.text().strip() or str(DEFAULT_DIR)).expanduser())
        chosen = QFileDialog.getExistingDirectory(self, "Wallpaper folder", current)
        if chosen:
            self.folder_edit.setText(chosen)
            self.scan()

    def open_dir(self) -> None:
        p = Path(self.folder_edit.text().strip()).expanduser()
        if not p.exists():
            QMessageBox.warning(self, APP_NAME, f"Folder not found:\n{p}")
            return
        try:
            subprocess.Popen(["xdg-open", str(p)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception as e:
            QMessageBox.critical(self, APP_NAME, f"Failed to open folder:\n{e}")

    def refresh_displays(self) -> None:
        names = [ALL_DISPLAYS]

        # Prefer Hyprland monitor list
        try:
            cp = run_cmd(["hyprctl", "-j", "monitors"], timeout=2.5)
            if cp.returncode == 0 and cp.stdout.strip():
                data = json.loads(cp.stdout)
                if isinstance(data, list):
                    for m in data:
                        n = str(m.get("name", "")).strip()
                        if n and n not in names:
                            names.append(n)
        except Exception:
            pass

        # Fallback to swww query
        if len(names) == 1:
            try:
                cp = run_cmd(["swww", "query"], timeout=2.5)
                if cp.returncode == 0:
                    for line in cp.stdout.splitlines():
                        if ":" in line:
                            n = line.split(":", 1)[0].strip()
                            if n and n not in names:
                                names.append(n)
            except Exception:
                pass

        cur = self.display_combo.currentText()
        self.display_combo.clear()
        self.display_combo.addItems(names)
        idx = self.display_combo.findText(cur)
        self.display_combo.setCurrentIndex(idx if idx >= 0 else 0)

    def available_output_names(self) -> list[str]:
        names: list[str] = []
        for i in range(self.display_combo.count()):
            n = self.display_combo.itemText(i).strip()
            if n and n != ALL_DISPLAYS and n not in names:
                names.append(n)
        return names

    def _iter_paths(self, root: Path):
        iterator = root.rglob("*") if self.recursive_check.isChecked() else root.iterdir()
        for p in iterator:
            if p.is_file() and p.suffix.lower() in SUPPORTED_EXTS:
                yield p

    def scan(self) -> None:
        folder = Path(self.folder_edit.text().strip() or str(DEFAULT_DIR)).expanduser()
        if not folder.is_dir():
            QMessageBox.warning(self, APP_NAME, f"Folder not found:\n{folder}")
            return

        self.refresh_displays()

        self.thumb_timer.stop()
        self.pending.clear()
        self.items.clear()
        self.filtered.clear()
        self.path_to_item.clear()
        self.path_to_widget.clear()
        self.grid.clear()
        self.btn_apply.setEnabled(False)
        self.selection_label.setText("No selection")

        self.status(f"Scanning {folder} ...")

        count = 0
        append_item = self.items.append
        set_item = self.path_to_item.__setitem__

        for p in self._iter_paths(folder):
            try:
                st = p.stat()
            except OSError:
                continue

            wi = WallItem(
                path=p,
                thumb_path=make_thumb_cache_path(p, st.st_mtime_ns, st.st_size),
                mtime_ns=st.st_mtime_ns,
                size_bytes=st.st_size,
            )
            append_item(wi)
            set_item(p, wi)
            count += 1

        self.items.sort(key=lambda x: str(x.path).lower())
        self.apply_filter()
        self.status(f"Found {count} wallpapers")

    def apply_filter(self) -> None:
        term = self.search_edit.text().strip().lower()
        if term:
            self.filtered = [
                w for w in self.items
                if term in w.path.name.lower() or term in str(w.path.parent).lower()
            ]
        else:
            self.filtered = list(self.items)
        self._rebuild_grid()

    def _rebuild_grid(self) -> None:
        self.thumb_timer.stop()
        self.pending.clear()
        self.path_to_widget.clear()
        self.grid.clear()
        self.btn_apply.setEnabled(False)
        self.selection_label.setText("No selection")

        if not self.filtered:
            self.status("No wallpapers match current filter")
            return

        ph_icon = QIcon(placeholder_pixmap(ICON_SIZE, "Loading"))

        self.grid.setUpdatesEnabled(False)
        try:
            path_to_widget_set = self.path_to_widget.__setitem__
            grid_add = self.grid.addItem
            pending_append = self.pending.append

            for w in self.filtered:
                item = QListWidgetItem(ph_icon, w.path.name)
                item.setData(Qt.ItemDataRole.UserRole, str(w.path))
                item.setToolTip(str(w.path))
                item.setTextAlignment(int(Qt.AlignmentFlag.AlignHCenter | Qt.AlignmentFlag.AlignTop))
                grid_add(item)
                path_to_widget_set(w.path, item)
                pending_append(w)
        finally:
            self.grid.setUpdatesEnabled(True)
            self.grid.viewport().update()

        self.status(f"Loading thumbnails... 0/{len(self.filtered)}")
        self.thumb_timer.start(0)

    def _thumb_tick(self) -> None:
        # Slightly larger batch improves throughput while remaining responsive
        batch = 24

        for _ in range(min(batch, len(self.pending))):
            w = self.pending.pop(0)
            try:
                ensure_thumb(w)
                raw = QPixmap(str(w.thumb_path))
                item = self.path_to_widget.get(w.path)
                if item is not None:
                    if raw.isNull():
                        item.setIcon(QIcon(placeholder_pixmap(ICON_SIZE, "No Preview")))
                    else:
                        # Thumbnail cache is already generated at icon size (240x150)
                        item.setIcon(QIcon(raw))
            except Exception:
                pass

        loaded = len(self.filtered) - len(self.pending)
        self.status(f"Loading thumbnails... {loaded}/{len(self.filtered)}")
        if not self.pending:
            self.thumb_timer.stop()
            self.status(f"Ready • {len(self.filtered)} wallpapers")

    def selected_wall(self) -> Optional[WallItem]:
        item = self.grid.currentItem()
        if item is None:
            return None
        p = item.data(Qt.ItemDataRole.UserRole)
        if not p:
            return None
        return self.path_to_item.get(Path(p))

    def on_selection_changed(self, current, _previous) -> None:
        if current is None:
            self.btn_apply.setEnabled(False)
            self.selection_label.setText("No selection")
            return

        p = current.data(Qt.ItemDataRole.UserRole)
        if not p:
            self.btn_apply.setEnabled(False)
            self.selection_label.setText("No selection")
            return

        self.btn_apply.setEnabled(True)
        self.selection_label.setText(str(p))

    # ---------- swww backend ----------
    def ensure_swww_daemon(self) -> bool:
        try:
            cp = run_cmd(["swww", "query"], timeout=1.5)
            if cp.returncode == 0:
                return True
        except Exception:
            pass

        try:
            subprocess.Popen(
                ["swww-daemon"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except FileNotFoundError:
            QMessageBox.critical(self, APP_NAME, "swww not installed (missing swww-daemon).")
            return False
        except Exception as e:
            QMessageBox.critical(self, APP_NAME, f"Failed to start swww-daemon:\n{e}")
            return False

        deadline = time.time() + 4.0
        while time.time() < deadline:
            try:
                cp = run_cmd(["swww", "query"], timeout=1.0)
                if cp.returncode == 0:
                    return True
            except Exception:
                pass
            time.sleep(0.2)

        QMessageBox.critical(self, APP_NAME, "swww-daemon did not become ready.")
        return False

    def build_swww_cmd(self, img: Path, outputs: list[str]) -> list[str]:
        cmd = ["swww", "img"]

        if outputs:
            cmd += ["--outputs", ",".join(outputs)]

        resize = self.resize_combo.currentText().strip()
        if resize:
            cmd += ["--resize", resize]

        transition = self.transition_combo.currentText().strip()
        if transition:
            cmd += ["--transition-type", transition]

        dur = self.duration_edit.text().strip()
        if dur:
            cmd += ["--transition-duration", dur]

        fps = self.fps_edit.text().strip()
        if fps:
            cmd += ["--transition-fps", fps]

        filt = self.filter_combo.currentText().strip()
        if filt:
            cmd += ["--filter", filt]

        cmd.append(str(img))
        return cmd

    def apply_with_swww(self, img: Path, outputs: list[str]) -> tuple[bool, str]:
        if not self.ensure_swww_daemon():
            return False, "swww daemon unavailable"

        cmd = self.build_swww_cmd(img, outputs)
        try:
            cp = run_cmd(cmd, timeout=25.0)
        except FileNotFoundError:
            return False, "swww not installed"
        except Exception as e:
            return False, str(e)

        if cp.returncode != 0:
            return False, (cp.stderr or cp.stdout or "unknown swww error").strip()
        return True, ""

    # ---------- hyprpaper backend ----------
    def ensure_hyprpaper(self) -> bool:
        try:
            cp = run_cmd(["hyprctl", "hyprpaper", "listactive"], timeout=1.5)
            if cp.returncode == 0:
                return True
        except Exception:
            pass

        try:
            subprocess.Popen(
                ["hyprpaper"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except FileNotFoundError:
            QMessageBox.critical(self, APP_NAME, "hyprpaper not installed.")
            return False
        except Exception as e:
            QMessageBox.critical(self, APP_NAME, f"Failed to start hyprpaper:\n{e}")
            return False

        deadline = time.time() + 4.0
        while time.time() < deadline:
            try:
                cp = run_cmd(["hyprctl", "hyprpaper", "listactive"], timeout=1.0)
                if cp.returncode == 0:
                    return True
            except Exception:
                pass
            time.sleep(0.2)

        QMessageBox.critical(self, APP_NAME, "hyprpaper IPC not ready.")
        return False

    def hyprpaper_mode(self) -> str:
        return self.hyprpaper_mode_combo.currentText().strip() or "cover"

    def hyprpaper_call(self, dispatcher: str, arg: str, timeout: float = 5.0) -> tuple[bool, str]:
        try:
            cp = run_cmd(["hyprctl", "hyprpaper", dispatcher, arg], timeout=timeout)
        except Exception as e:
            return False, str(e)

        if cp.returncode != 0:
            return False, (cp.stderr or cp.stdout or "hyprpaper IPC error").strip()
        return True, ""

    def apply_with_hyprpaper(self, img: Path, outputs: list[str]) -> tuple[bool, str]:
        if not self.ensure_hyprpaper():
            return False, "hyprpaper unavailable"

        ok, err = self.hyprpaper_call("preload", str(img))
        if not ok:
            return False, f"preload failed: {err}"

        mode = self.hyprpaper_mode()

        for out in outputs:
            # Try newer syntax with mode, fall back to plain syntax if unsupported
            ok, err = self.hyprpaper_call("wallpaper", f"{out},{img},{mode}")
            if not ok:
                ok2, err2 = self.hyprpaper_call("wallpaper", f"{out},{img}")
                if not ok2:
                    return False, f"{out}: {err} | fallback failed: {err2}"

        return True, ""

    # ---------- apply ----------
    def resolve_target_outputs(self) -> list[str]:
        display = self.display_combo.currentText().strip()
        if not display or display == ALL_DISPLAYS:
            return self.available_output_names()
        return [display]

    def apply_selected(self) -> None:
        wall = self.selected_wall()
        if wall is None:
            return
        self._apply_wall(wall.path)

    def apply_random(self) -> None:
        if not self.filtered:
            return
        wall = random.choice(self.filtered)
        li = self.path_to_widget.get(wall.path)
        if li is not None:
            self.grid.setCurrentItem(li)
        self._apply_wall(wall.path)

    def _apply_wall(self, path: Path) -> None:
        outputs = self.resolve_target_outputs()
        if not outputs:
            QMessageBox.warning(self, APP_NAME, "No outputs detected.")
            return

        backend = self.backend_combo.currentText().strip() or "swww"
        self.status(f"Applying {path.name} via {backend} ...")

        if backend == "swww":
            ok, err = self.apply_with_swww(path, outputs)
        else:
            ok, err = self.apply_with_hyprpaper(path, outputs)

        if not ok:
            QMessageBox.critical(self, APP_NAME, f"{backend} apply failed:\n{err}")
            self.status("Apply failed")
            return

        self.status(f"Applied {path.name} -> {', '.join(outputs)} ({backend})")


def main() -> int:
    script_path = Path(__file__).resolve()
    ensure_local_desktop_file(script_path)

    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    app.setDesktopFileName(APP_ID)  # stable Wayland app_id/class for Hyprland matching

    w = MainWindow()
    w.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
