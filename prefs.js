import { ExtensionPreferences } from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';
import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';
import Gdk from 'gi://Gdk';

export default class ForceQuitPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        window.search_enabled = true;

        const settings = this.getSettings();

        const page = new Adw.PreferencesPage({
            title: 'General',
            icon_name: 'dialog-information-symbolic',
        });
        window.add(page);

        // SIGKILL Group
        const sigkillGroup = new Adw.PreferencesGroup({
            title: 'Force Kill (SIGKILL)',
            description: 'Instantly destroys the process. Unsaved data will be lost.',
        });
        page.add(sigkillGroup);

        const sigkillKeyRow = new Adw.ActionRow({
            title: 'SIGKILL Keybind',
            subtitle: 'Key to hold when clicking the window close button.',
        });
        this._setupKeybind(settings, 'sigkill-key', sigkillKeyRow);
        sigkillGroup.add(sigkillKeyRow);

        const sigkillColorRow = new Adw.ActionRow({
            title: 'SIGKILL Glow Color',
            subtitle: 'Color of the close button when armed.',
        });
        const sigkillColorButton = new Gtk.ColorDialogButton({
            dialog: new Gtk.ColorDialog(),
            valign: Gtk.Align.CENTER,
        });
        sigkillColorRow.add_suffix(sigkillColorButton);
        sigkillGroup.add(sigkillColorRow);

        this._bindColorSetting(settings, 'sigkill-color', sigkillColorButton);


        // SIGTERM Group
        const sigtermGroup = new Adw.PreferencesGroup({
            title: 'Graceful Kill (SIGTERM)',
            description: 'Requests the process to terminate. The application can catch this and save data.',
        });
        page.add(sigtermGroup);

        const sigtermKeyRow = new Adw.ActionRow({
            title: 'SIGTERM Keybind',
            subtitle: 'Key to hold when clicking the window close button.',
        });
        this._setupKeybind(settings, 'sigterm-key', sigtermKeyRow);
        sigtermGroup.add(sigtermKeyRow);

        const sigtermColorRow = new Adw.ActionRow({
            title: 'SIGTERM Glow Color',
            subtitle: 'Color of the close button when armed.',
        });
        const sigtermColorButton = new Gtk.ColorDialogButton({
            dialog: new Gtk.ColorDialog(),
            valign: Gtk.Align.CENTER,
        });
        sigtermColorRow.add_suffix(sigtermColorButton);
        sigtermGroup.add(sigtermColorRow);

        this._bindColorSetting(settings, 'sigterm-color', sigtermColorButton);


        // Misc Group
        const miscGroup = new Adw.PreferencesGroup({
            title: 'Miscellaneous',
        });
        page.add(miscGroup);

        const notificationsRow = new Adw.SwitchRow({
            title: 'Enable Notifications',
            subtitle: 'Show a desktop notification when a window is killed.',
        });
        miscGroup.add(notificationsRow);
        settings.bind('enable-notifications', notificationsRow, 'active', Gio.SettingsBindFlags.DEFAULT);
    }

    _setupKeybind(settings, key, row) {
        const button = new Gtk.Button({
            valign: Gtk.Align.CENTER,
        });
        
        // Ensure the button is wide enough to show the "Press any key..." text
        button.set_size_request(200, -1);

        const updateLabel = () => {
            const keyval = settings.get_int(key);
            if (keyval === 0) {
                button.label = 'None';
            } else {
                const name = Gdk.keyval_name(keyval);
                button.label = name ? name : `Keyval ${keyval}`;
            }
        };

        updateLabel();
        settings.connect(`changed::${key}`, updateLabel);

        let keyController = null;

        button.connect('clicked', () => {
            if (keyController) {
                // If clicked again while listening, just cancel
                button.remove_controller(keyController);
                keyController = null;
                updateLabel();
                return;
            }

            button.label = 'Press any key (Esc to cancel)...';
            
            keyController = new Gtk.EventControllerKey();
            button.add_controller(keyController);
            
            // Give button focus so the controller receives key events
            button.grab_focus();

            keyController.connect('key-pressed', (controller, keyval, keycode, state) => {
                // If Escape (65307) or Backspace (65288), cancel or clear
                if (keyval === Gdk.KEY_Escape) {
                    // Just cancel
                } else if (keyval === Gdk.KEY_BackSpace) {
                    // Clear the bind
                    settings.set_int(key, 0);
                } else {
                    // Save the new keybind
                    settings.set_int(key, keyval);
                }

                button.remove_controller(keyController);
                keyController = null;
                updateLabel();
                
                // Returning true stops the event from propagating
                return true; 
            });
            
            // If focus is lost, cancel listening
            button.connect('notify::has-focus', () => {
                if (!button.has_focus && keyController) {
                    button.remove_controller(keyController);
                    keyController = null;
                    updateLabel();
                }
            });
        });

        row.add_suffix(button);
    }

    _bindColorSetting(settings, key, colorButton) {
        // Init color
        const rgba = new Gdk.RGBA();
        rgba.parse(settings.get_string(key));
        colorButton.rgba = rgba;

        // When button color changes, save to settings
        colorButton.connect('notify::rgba', () => {
            const newRgba = colorButton.rgba;
            settings.set_string(key, newRgba.to_string());
        });

        // When settings change from outside, update button
        settings.connect(`changed::${key}`, () => {
            const newRgba = new Gdk.RGBA();
            newRgba.parse(settings.get_string(key));
            if (colorButton.rgba.to_string() !== newRgba.to_string()) {
                colorButton.rgba = newRgba;
            }
        });
    }
}
