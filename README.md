# ForceQuit GNOME Shell Extension

**ForceQuit** is a modern GNOME Shell extension (compatible with GNOME Shell 45 through 50+) that allows you to immediately force kill hanging or unresponsive applications by holding the **Shift** key while clicking the close (X) button on the window titlebar or in the GNOME Shell Overview.

Instead of waiting for a graceful quit request (`WM_DELETE_WINDOW`) to timeout or freeze your system, **ForceQuit** sends `SIGKILL` (`kill -9`) directly to the process and notifies you with details (App Title and PID).

---

## Features

- **Instant Process Termination**: Forcefully kills frozen apps without delay when holding **Shift** + clicking Close (X).
- **Red Glow Visual Feedback**: The close button highlights with a red glow when Shift is held, visually indicating that force kill mode is armed.
- **Overview & Titlebar Support**: Works in both the GNOME Shell Overview (`WindowPreview` cards) and window titlebar close actions.
- **Desktop Notifications**: Displays desktop notification feedback showing the terminated app's name and PID.
- **Universal & Portable**: Works across any user account and Linux distribution running GNOME Shell 45+.

---

## Installation

### Automated Installation (Recommended)

Run the included universal installer script. It automatically detects the user's home directory and XDG data paths:

```bash
cd ForceQuit
./install.sh
```

### Manual Installation

Copy the project directory into your GNOME extensions folder:

```bash
mkdir -p ~/.local/share/gnome-shell/extensions/forcequit@schirelli.github.io
cp metadata.json extension.js stylesheet.css ~/.local/share/gnome-shell/extensions/forcequit@schirelli.github.io/
gnome-extensions enable forcequit@schirelli.github.io
```

---

## Usage

1. **Normal Close**: Click the close (X) button as usual -> The application closes gracefully.
2. **Force Quit**: Hold the **Shift** key while clicking the close (X) button -> The process is forcefully killed (`kill -9 PID`), and a desktop notification confirms the termination.

---

## Reloading GNOME Shell

- **Wayland**: Log out and log back in (or restart your session).
- **X11**: Press `Alt + F2`, type `r`, and press `Enter`.
