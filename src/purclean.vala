/*
 * Purclean
 * Copyright (C) 2026 BYOVAL STUDIO
 */

public class Purclean.Application : Adw.Application {

    public Application () {
        Object (
            application_id: "com.github.byoval.purclean",
            flags: ApplicationFlags.DEFAULT_FLAGS
        );
    }

    protected override void startup () {
        base.startup ();

        /* Apply language override BEFORE locale initialisation so that
         * gettext picks up the right catalogue on first use.            */
        string lang = AppSettings.get_instance ().language;
        if (lang != "auto") {
            /* e.g. "ru" → set LANGUAGE=ru:en, LANG=ru_RU.UTF-8 */
            string locale = (lang == "ru") ? "ru_RU.UTF-8" : "en_US.UTF-8";
            Environment.set_variable ("LANGUAGE",  lang + ":en", true);
            Environment.set_variable ("LANG",      locale,       true);
            Environment.set_variable ("LC_ALL",    locale,       true);
        }

        Intl.setlocale (LocaleCategory.ALL, "");
        Intl.bindtextdomain (GETTEXT_PACKAGE, LOCALEDIR);
        Intl.bind_textdomain_codeset (GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (GETTEXT_PACKAGE);
    }

    protected override void activate () {
        var win = this.active_window;
        if (win == null) {
            win = new Purclean.Window (this);
        }
        win.present ();
    }

    public static int main (string[] args) {
        return new Application ().run (args);
    }
}
