import GObject from 'gi://GObject';
import GLib from 'gi://GLib';
import Gio from 'gi://Gio';
import St from 'gi://St';
import Clutter from 'gi://Clutter';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PanelMenu from 'resource:///org/gnome/shell/ui/panelMenu.js';

import { Extension } from 'resource:///org/gnome/shell/extensions/extension.js';

// ─── Paths ────────────────────────────────────────────────────────────────────
const DATA_DIR    = GLib.build_filenamev([GLib.get_home_dir(), '.worktracker']);
const STATE_FILE  = GLib.build_filenamev([DATA_DIR, '.state']);
const PAUSED_FILE = GLib.build_filenamev([DATA_DIR, '.paused']);

// ─── Icons ────────────────────────────────────────────────────────────────────
const ICON_RUNNING = 'media-playback-start-symbolic';
const ICON_PAUSED  = 'media-playback-pause-symbolic';
const ICON_IDLE    = 'media-record-symbolic';

// ─── Helpers ─────────────────────────────────────────────────────────────────
function readFileSync(path) {
    try {
        const file = Gio.File.new_for_path(path);
        const [ok, contents] = file.load_contents(null);
        if (!ok) return null;
        return new TextDecoder('utf-8').decode(contents).trim();
    } catch (_) {
        return null;
    }
}

function formatTime(seconds) {
    seconds = Math.max(0, Math.floor(seconds));
    const h = Math.floor(seconds / 3600);
    const m = Math.floor((seconds % 3600) / 60);
    const s = seconds % 60;
    return `${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}:${String(s).padStart(2,'0')}`;
}

// ─── Indicator ───────────────────────────────────────────────────────────────
// Uses PanelMenu.Button (no menu) so font + spacing match the panel natively.
// reactive: false kills all hover/click behaviour — no highlight, no margin shift.
const WorkTrackerIndicator = GObject.registerClass(
class WorkTrackerIndicator extends PanelMenu.Button {

    _init(settings) {
        super._init(0.0, 'WorkTracker', true); // true = no menu

        // Disable all interaction — purely display
        this.reactive  = false;
        this.can_focus = false;
        this.track_hover = false;

        this._settings = settings;

        this._icon = new St.Icon({
            icon_name: ICON_IDLE,
            style_class: 'system-status-icon',
        });

        // No custom font-size — inherits the panel's own font naturally
        this._label = new St.Label({
            text: '',
            y_align: Clutter.ActorAlign.CENTER,
            style: 'margin-left: 4px;',
        });

        const box = new St.BoxLayout({ style_class: 'panel-status-menu-box' });
        box.add_child(this._icon);
        box.add_child(this._label);
        this.add_child(box);

        this._settingsConnId = this._settings.connect('changed', () => this.refresh());
    }

    refresh() {
        // Read both files fresh every tick
        const stateRaw  = readFileSync(STATE_FILE);
        const pausedRaw = readFileSync(PAUSED_FILE);

        const showProject = this._settings.get_boolean('show-project-name');
        const showIdle    = this._settings.get_boolean('show-when-idle');

        if (stateRaw && !pausedRaw) {
            // ── RUNNING: STATE_FILE present, no PAUSED_FILE ──────────────────
            const parts     = stateRaw.split(',');
            const project   = parts[0] || 'Unknown';
            const startTime = parseInt(parts[1], 10) || 0;
            const elapsed   = Math.floor(Date.now() / 1000) - startTime;

            this._icon.icon_name = ICON_RUNNING;
            this._icon.set_style('color: #57e389;');
            this._label.set_text(showProject ? `${formatTime(elapsed)}  ${project}` : formatTime(elapsed));
            this.show();

        } else if (pausedRaw) {
            // ── PAUSED: PAUSED_FILE present (STATE_FILE may or may not exist) ─
            const parts   = pausedRaw.split(',');
            const project = parts[0] || 'Unknown';
            const elapsed = parseInt(parts[1], 10) || 0;

            this._icon.icon_name = ICON_PAUSED;
            this._icon.set_style('color: #f9f06b;');
            this._label.set_text(showProject ? `${formatTime(elapsed)}  ${project}` : formatTime(elapsed));
            this.show();

        } else {
            // ── IDLE: neither file exists ─────────────────────────────────────
            this._icon.icon_name = ICON_IDLE;
            this._icon.set_style('color: rgba(255,255,255,0.45);');
            this._label.set_text(showIdle ? 'Idle' : '');
            if (showIdle) this.show(); else this.hide();
        }
    }

    destroy() {
        if (this._settingsConnId) {
            this._settings.disconnect(this._settingsConnId);
            this._settingsConnId = null;
        }
        super.destroy();
    }
});

// ─── Extension ───────────────────────────────────────────────────────────────
export default class WorkTrackerExtension extends Extension {

    enable() {
        this._settings  = this.getSettings();
        this._timeoutId = null;

        this._buildIndicator();

        this._posConnId = this._settings.connect('changed::panel-position', () => {
            this._destroyIndicator();
            this._buildIndicator();
        });
    }

    _buildIndicator() {
        this._indicator = new WorkTrackerIndicator(this._settings);

        // Clear any stale registry entry
        if (Main.panel.statusArea['worktracker'])
            delete Main.panel.statusArea['worktracker'];

        const pos   = this._settings.get_string('panel-position');
        const index = pos === 'right' ? 0 : -1;
        Main.panel.addToStatusArea('worktracker', this._indicator, index, pos);

        // Poll every second — reads state files fresh each tick
        this._indicator.refresh();
        this._timeoutId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 1, () => {
            if (this._indicator) {
                this._indicator.refresh();
                return GLib.SOURCE_CONTINUE;
            }
            return GLib.SOURCE_REMOVE;
        });
    }

    _destroyIndicator() {
        if (this._timeoutId) {
            GLib.source_remove(this._timeoutId);
            this._timeoutId = null;
        }
        if (this._indicator) {
            if (Main.panel.statusArea['worktracker'] === this._indicator)
                delete Main.panel.statusArea['worktracker'];
            this._indicator.destroy();
            this._indicator = null;
        }
    }

    disable() {
        if (this._posConnId) {
            this._settings.disconnect(this._posConnId);
            this._posConnId = null;
        }
        this._destroyIndicator();
        this._settings = null;
    }
}
