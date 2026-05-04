import Adw from 'gi://Adw';
import Gio from 'gi://Gio';
import Gtk from 'gi://Gtk';

import { ExtensionPreferences } from 'resource:///org/gnome/Shell/Extensions/js/extensions/prefs.js';

export default class WorkTrackerPreferences extends ExtensionPreferences {
    fillPreferencesWindow(window) {
        const settings = this.getSettings();

        // ── Page ──────────────────────────────────────────────────────────────
        const page = new Adw.PreferencesPage({
            title: 'Work Tracker',
            icon_name: 'utilities-terminal-symbolic',
        });
        window.add(page);

        // ── Display group ─────────────────────────────────────────────────────
        const displayGroup = new Adw.PreferencesGroup({
            title: 'Panel Display',
            description: 'Control what is shown in the top panel.',
        });
        page.add(displayGroup);

        // Panel Position (ComboRow)
        const positionRow = new Adw.ComboRow({
            title: 'Panel Position',
            subtitle: 'Where to place the Work Tracker indicator.',
            model: new Gtk.StringList({ strings: ['Left', 'Center', 'Right'] }),
        });

        // Map setting value → index
        const posMap = { 'left': 0, 'center': 1, 'right': 2 };
        const posRevMap = ['left', 'center', 'right'];
        const currentPos = settings.get_string('panel-position');
        positionRow.selected = posMap[currentPos] ?? 2;

        positionRow.connect('notify::selected', () => {
            settings.set_string('panel-position', posRevMap[positionRow.selected]);
        });

        displayGroup.add(positionRow);

        // Show Project Name (SwitchRow)
        const showProjectRow = new Adw.SwitchRow({
            title: 'Show Project Name',
            subtitle: 'Display the project name next to the timer.',
        });
        settings.bind('show-project-name', showProjectRow, 'active', Gio.SettingsBindFlags.DEFAULT);
        displayGroup.add(showProjectRow);

        // Show When Idle (SwitchRow)
        const showIdleRow = new Adw.SwitchRow({
            title: 'Show When Idle',
            subtitle: 'Keep the indicator visible even when no session is running.',
        });
        settings.bind('show-when-idle', showIdleRow, 'active', Gio.SettingsBindFlags.DEFAULT);
        displayGroup.add(showIdleRow);

        // ── About group ───────────────────────────────────────────────────────
        const aboutGroup = new Adw.PreferencesGroup({ title: 'About' });
        page.add(aboutGroup);

        const aboutRow = new Adw.ActionRow({
            title: 'Work Tracker',
            subtitle: 'Terminal timer companion for GNOME Shell • v1.0',
            icon_name: 'utilities-terminal-symbolic',
        });
        aboutGroup.add(aboutRow);

        const stateRow = new Adw.ActionRow({
            title: 'State Files',
            subtitle: '~/.worktracker/.state  |  ~/.worktracker/.paused',
            icon_name: 'folder-documents-symbolic',
        });
        aboutGroup.add(stateRow);
    }
}
