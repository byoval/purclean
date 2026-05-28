/*
 * Purclean — AppSettings
 * Copyright (C) 2026 BYOVAL STUDIO
 *
 * Singleton wrapper around GLib.Settings.
 */

public class Purclean.AppSettings : Object {

    private static AppSettings? _instance = null;
    private GLib.Settings _s;

    public static AppSettings get_instance () {
        if (_instance == null) _instance = new AppSettings ();
        return _instance;
    }

    private AppSettings () {
        _s = new GLib.Settings ("com.github.byoval.purclean");
    }

    /* ---- Analysis ---- */

    public int archive_min_mb {
        get { return _s.get_int ("archive-min-mb"); }
        set { _s.set_int ("archive-min-mb", value); }
    }

    public int find_max_depth {
        get { return _s.get_int ("find-max-depth"); }
        set { _s.set_int ("find-max-depth", value); }
    }

    public int journal_retention_days {
        get { return _s.get_int ("journal-retention-days"); }
        set { _s.set_int ("journal-retention-days", value); }
    }

    public int duplicate_min_mb {
        get { return _s.get_int ("duplicate-min-mb"); }
        set { _s.set_int ("duplicate-min-mb", value); }
    }

    /* ---- Notifications ---- */

    public bool notifications_enabled {
        get { return _s.get_boolean ("notifications-enabled"); }
        set { _s.set_boolean ("notifications-enabled", value); }
    }

    public int disk_warning_percent {
        get { return _s.get_int ("disk-warning-percent"); }
        set { _s.set_int ("disk-warning-percent", value); }
    }

    /* ---- Appearance ---- */

    /* "default" | "prefer-dark" | "prefer-light" */
    public string color_scheme {
        owned get { return _s.get_string ("color-scheme"); }
        set { _s.set_string ("color-scheme", value); }
    }

    /* ---- Language ---- */

    /* "auto" | "en" | "ru" */
    public string language {
        owned get { return _s.get_string ("language"); }
        set { _s.set_string ("language", value); }
    }

    /* Convenience: bind a GObject property to a settings key */
    public void bind (string key, Object obj, string property,
                      GLib.SettingsBindFlags flags = GLib.SettingsBindFlags.DEFAULT) {
        _s.bind (key, obj, property, flags);
    }
}
