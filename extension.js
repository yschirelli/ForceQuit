import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';
import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import { WindowPreview } from 'resource:///org/gnome/shell/ui/windowPreview.js';
import Clutter from 'gi://Clutter';
import Meta from 'gi://Meta';
import GLib from 'gi://GLib';

let activeExtensionInstance = null;

// Preserve unpatched original prototype functions statically
const origWindowPreviewDeleteAll = WindowPreview.prototype._forcequit_origDeleteAll || WindowPreview.prototype._deleteAll;
const origWindowPreviewShowOverlay = WindowPreview.prototype._forcequit_origShowOverlay || WindowPreview.prototype.showOverlay;
const origWindowPreviewHideOverlay = WindowPreview.prototype._forcequit_origHideOverlay || WindowPreview.prototype.hideOverlay;
const origMetaWindowDelete = Meta.Window.prototype._forcequit_origDelete || Meta.Window.prototype.delete;

if (!WindowPreview.prototype._forcequit_patched) {
    WindowPreview.prototype._forcequit_origDeleteAll = origWindowPreviewDeleteAll;
    WindowPreview.prototype._forcequit_origShowOverlay = origWindowPreviewShowOverlay;
    WindowPreview.prototype._forcequit_origHideOverlay = origWindowPreviewHideOverlay;
    WindowPreview.prototype._forcequit_patched = true;

    WindowPreview.prototype.showOverlay = function (animate) {
        if (origWindowPreviewShowOverlay) {
            origWindowPreviewShowOverlay.call(this, animate);
        }
        if (activeExtensionInstance) {
            activeExtensionInstance._registerPreview(this);
            activeExtensionInstance._updatePreviewCloseButton(this);
        }
    };

    WindowPreview.prototype.hideOverlay = function (animate) {
        if (origWindowPreviewHideOverlay) {
            origWindowPreviewHideOverlay.call(this, animate);
        }
        if (activeExtensionInstance) {
            activeExtensionInstance._updatePreviewCloseButton(this);
        }
    };

    WindowPreview.prototype._deleteAll = function () {
        const mode = (activeExtensionInstance && Main.overview.visible) ? activeExtensionInstance._activeMode : null;
        if (mode && activeExtensionInstance) {
            if (this.metaWindow) {
                activeExtensionInstance._killWindow(this.metaWindow, mode);
            }
            this._closeRequested = true;
            return;
        }
        return origWindowPreviewDeleteAll.call(this);
    };
}

if (!Meta.Window.prototype._forcequit_patched) {
    Meta.Window.prototype._forcequit_origDelete = origMetaWindowDelete;
    Meta.Window.prototype._forcequit_patched = true;

    Meta.Window.prototype.delete = function (timestamp) {
        const mode = (activeExtensionInstance && Main.overview.visible) ? activeExtensionInstance._activeMode : null;
        if (mode && activeExtensionInstance) {
            activeExtensionInstance._killWindow(this, mode);
            return;
        }
        return origMetaWindowDelete.call(this, timestamp);
    };
}

export default class ForceQuitExtension extends Extension {
    enable() {
        activeExtensionInstance = this;

        this._settings = this.getSettings();
        
        // Settings State
        this._sigkillKey = this._settings.get_int('sigkill-key');
        this._sigtermKey = this._settings.get_int('sigterm-key');
        this._sigkillColor = this._settings.get_string('sigkill-color');
        this._sigtermColor = this._settings.get_string('sigterm-color');
        
        this._settingsChangedId = this._settings.connect('changed', (settings, key) => {
            if (key === 'sigkill-key') this._sigkillKey = settings.get_int(key);
            if (key === 'sigterm-key') this._sigtermKey = settings.get_int(key);
            if (key === 'sigkill-color') this._sigkillColor = settings.get_string(key);
            if (key === 'sigterm-color') this._sigtermColor = settings.get_string(key);
            this._checkActiveMode();
        });

        this._activeMode = null; // 'sigkill', 'sigterm', or null
        this._activePreviews = new Set();
        this._heldKeys = new Set(); // Store raw key symbols
        this._capturedEventId = 0;

        // Only track modifier keys when the overview (super menu) is showing/shown
        this._overviewShowingId = Main.overview.connect('showing', () => {
            this._startKeyTracking();
        });

        this._overviewHidingId = Main.overview.connect('hiding', () => {
            this._stopKeyTracking();
        });

        this._overviewHiddenId = Main.overview.connect('hidden', () => {
            this._stopKeyTracking();
        });

        if (Main.overview.visible) {
            this._startKeyTracking();
        }
    }

    disable() {
        if (activeExtensionInstance === this) {
            activeExtensionInstance = null;
        }

        if (this._overviewShowingId) {
            Main.overview.disconnect(this._overviewShowingId);
            this._overviewShowingId = 0;
        }
        if (this._overviewHidingId) {
            Main.overview.disconnect(this._overviewHidingId);
            this._overviewHidingId = 0;
        }
        if (this._overviewHiddenId) {
            Main.overview.disconnect(this._overviewHiddenId);
            this._overviewHiddenId = 0;
        }

        this._stopKeyTracking();

        if (this._settingsChangedId) {
            this._settings.disconnect(this._settingsChangedId);
            this._settingsChangedId = 0;
        }
        this._settings = null;

        if (this._activePreviews) {
            for (const preview of this._activePreviews) {
                if (preview && preview._closeButton) {
                    preview._closeButton.remove_style_class_name('forcequit-close-armed');
                    preview._closeButton.style = '';
                }
            }
            this._activePreviews.clear();
        }

        this._activeMode = null;
        this._heldKeys.clear();
    }

    _startKeyTracking() {
        if (this._capturedEventId) return;

        this._heldKeys.clear();
        this._checkActiveMode();

        this._capturedEventId = global.stage.connect('captured-event', (actor, event) => {
            const type = event.type();

            if (type === Clutter.EventType.KEY_PRESS) {
                const symbol = event.get_key_symbol();
                if (symbol) {
                    this._heldKeys.add(symbol);
                    this._checkActiveMode();
                }
            } else if (type === Clutter.EventType.KEY_RELEASE) {
                const symbol = event.get_key_symbol();
                if (symbol) {
                    this._heldKeys.delete(symbol);
                    this._checkActiveMode();
                }
            }

            return Clutter.EVENT_PROPAGATE;
        });
    }

    _stopKeyTracking() {
        if (this._capturedEventId) {
            global.stage.disconnect(this._capturedEventId);
            this._capturedEventId = 0;
        }

        this._heldKeys.clear();
        this._activeMode = null;
        this._updateAllCloseButtons();
    }

    _checkActiveMode() {
        let newMode = null;
        
        // Only evaluate active mode when tracking is active in overview
        if (this._capturedEventId) {
            // Check sigkill first for priority
            if (this._sigkillKey !== 0 && this._heldKeys.has(this._sigkillKey)) {
                newMode = 'sigkill';
            } else if (this._sigtermKey !== 0 && this._heldKeys.has(this._sigtermKey)) {
                newMode = 'sigterm';
            }
        }

        if (newMode !== this._activeMode) {
            this._activeMode = newMode;
            this._updateAllCloseButtons();
        }
    }

    _registerPreview(preview) {
        if (!preview) return;
        this._activePreviews.add(preview);
        if (typeof preview.connect === 'function') {
            preview.connect('destroy', () => {
                this._activePreviews.delete(preview);
            });
        }
    }

    _updateAllCloseButtons() {
        if (!this._activePreviews) return;

        for (const preview of this._activePreviews) {
            this._updatePreviewCloseButton(preview);
        }
    }

    _updatePreviewCloseButton(preview) {
        if (preview && preview._closeButton) {
            if (this._activeMode === 'sigkill') {
                preview._closeButton.add_style_class_name('forcequit-close-armed');
                preview._closeButton.style = `background-color: ${this._sigkillColor} !important; color: #ffffff !important; box-shadow: 0 0 12px ${this._sigkillColor} !important; border-radius: 99px;`;
            } else if (this._activeMode === 'sigterm') {
                preview._closeButton.add_style_class_name('forcequit-close-armed');
                preview._closeButton.style = `background-color: ${this._sigtermColor} !important; color: #ffffff !important; box-shadow: 0 0 12px ${this._sigtermColor} !important; border-radius: 99px;`;
            } else {
                preview._closeButton.remove_style_class_name('forcequit-close-armed');
                preview._closeButton.style = '';
            }
        }
    }

    _killWindow(metaWindow, mode) {
        if (!metaWindow) return;

        const title = metaWindow.get_title() || 'Window';
        const pid = metaWindow.get_pid();

        if (mode === 'sigterm') {
            // Graceful termination
            if (pid > 0) {
                try {
                    GLib.spawn_command_line_async(`kill -15 ${pid}`);
                } catch (e) {
                    console.error(`[ForceQuit] Error spawning kill -15 for PID ${pid}: ${e}`);
                }
            } else {
                // Fallback to metaWindow.delete
                try {
                    origMetaWindowDelete.call(metaWindow, global.get_current_time());
                } catch (e) {}
            }
        } else if (mode === 'sigkill') {
            // SIGKILL
            try {
                if (typeof metaWindow.kill === 'function') {
                    metaWindow.kill();
                }
            } catch (e) {
                console.error(`[ForceQuit] Error calling metaWindow.kill(): ${e}`);
            }

            if (pid > 0) {
                try {
                    GLib.spawn_command_line_async(`kill -9 ${pid}`);
                } catch (e) {
                    console.error(`[ForceQuit] Error spawning kill -9 for PID ${pid}: ${e}`);
                }
            }
        }

        if (this._settings && this._settings.get_boolean('enable-notifications')) {
            const pidLabel = pid > 0 ? ` (PID: ${pid})` : '';
            const actionText = mode === 'sigkill' ? 'Forcefully killed' : 'Requested termination of';
            Main.notify('Force Quit', `${actionText} "${title}"${pidLabel}`);
        }
    }
}
