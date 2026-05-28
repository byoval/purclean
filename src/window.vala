/*
 * Purclean — Window
 * Copyright (C) 2026 BYOVAL STUDIO
 */

public class Purclean.Window : Adw.ApplicationWindow {

    private Adw.ViewStack      main_stack;
    private Adw.ToastOverlay   toast_overlay;
    private Gtk.Button         analyze_button;
    private Gtk.Box            results_box;
    private Gtk.ToggleButton   dry_run_btn;
    private Purclean.Cleaner   cleaner;
    private Purclean.AnalysisResult current_result;

    private const double[,] COLORS = {
        { 0.90, 0.32, 0.32 },  /* kernels    */
        { 0.33, 0.65, 0.95 },  /* flatpak    */
        { 0.55, 0.84, 0.68 },  /* snap       */
        { 1.00, 0.76, 0.30 },  /* appimages  */
        { 0.80, 0.55, 0.95 },  /* archives   */
        { 0.95, 0.60, 0.20 },  /* logs       */
        { 0.60, 0.60, 0.60 },  /* orphans    */
        { 0.95, 0.40, 0.40 },  /* trash      */
        { 0.30, 0.75, 0.85 },  /* browser    */
        { 0.70, 0.85, 0.40 },  /* thumbnails */
        { 0.40, 0.60, 0.95 },  /* dnf        */
        { 0.90, 0.50, 0.80 },  /* duplicates */
        { 0.50, 0.50, 0.50 },  /* docker     */
    };

    public Window (Purclean.Application app) {
        Object (
            application:    app,
            title:          _("Purclean"),
            default_width:  1040,
            default_height: 740
        );
        apply_color_scheme (AppSettings.get_instance ().color_scheme);
        cleaner = new Purclean.Cleaner ();
        build_ui ();
    }

    /* ------------------------------------------------------------------ */
    /* UI build                                                             */
    /* ------------------------------------------------------------------ */

    private void build_ui () {
        var toolbar_view = new Adw.ToolbarView ();
        var header       = new Adw.HeaderBar ();

        header.set_title_widget (
            new Adw.WindowTitle (_("Purclean"), _("Project Byoval Studio"))
        );

        /* Dry-run toggle */
        dry_run_btn = new Gtk.ToggleButton () {
            icon_name  = "media-playback-start-symbolic",
            tooltip_text = _("Режим симуляции — ничего не удаляет")
        };
        dry_run_btn.toggled.connect (() => {
            cleaner.dry_run = dry_run_btn.active;
            if (dry_run_btn.active)
                dry_run_btn.add_css_class ("suggested-action");
            else
                dry_run_btn.remove_css_class ("suggested-action");
        });
        header.pack_end (dry_run_btn);

        /* History button */
        var hist_btn = new Gtk.Button () {
            icon_name    = "document-open-recent-symbolic",
            tooltip_text = _("История очисток")
        };
        hist_btn.clicked.connect (show_history_dialog);
        header.pack_end (hist_btn);

        /* Settings button */
        var settings_btn = new Gtk.Button () {
            icon_name    = "preferences-system-symbolic",
            tooltip_text = _("Настройки")
        };
        settings_btn.clicked.connect (show_settings_dialog);
        header.pack_end (settings_btn);

        /* About / menu button */
        var menu_model = new GLib.Menu ();
        menu_model.append (_("О программе"), "win.about");

        var menu_btn = new Gtk.MenuButton () {
            icon_name  = "open-menu-symbolic",
            menu_model = menu_model
        };
        header.pack_end (menu_btn);

        /* Wire the about action */
        var about_action = new GLib.SimpleAction ("about", null);
        about_action.activate.connect (() => show_about_dialog ());
        this.add_action (about_action);

        toolbar_view.add_top_bar (header);

        main_stack = new Adw.ViewStack ();
        main_stack.add_named (build_welcome_page (), "welcome");
        main_stack.add_named (build_results_page (), "results");

        /* Wrap in a ToastOverlay so we can show language-change hints */
        toast_overlay = new Adw.ToastOverlay () { child = main_stack };
        toolbar_view.set_content (toast_overlay);
        this.set_content (toolbar_view);
    }

    private Gtk.Widget build_welcome_page () {
        var status = new Adw.StatusPage () {
            title       = _("Система чистая"),
            description = _("Нажмите кнопку ниже, чтобы найти ненужные файлы"),
            icon_name   = "edit-clear-all-symbolic",
            vexpand     = true
        };

        analyze_button = new Gtk.Button.with_label (_("Анализировать систему")) {
            halign = Gtk.Align.CENTER
        };
        analyze_button.add_css_class ("pill");
        analyze_button.add_css_class ("suggested-action");
        analyze_button.clicked.connect (on_analyze_clicked);

        status.child = analyze_button;
        return status;
    }

    private Gtk.Widget build_results_page () {
        var scroll = new Gtk.ScrolledWindow () {
            vexpand           = true,
            hscrollbar_policy = Gtk.PolicyType.NEVER
        };
        results_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 16) {
            margin_top    = 24,
            margin_bottom = 24,
            margin_start  = 24,
            margin_end    = 24
        };
        scroll.child = results_box;
        return scroll;
    }

    /* ------------------------------------------------------------------ */
    /* Analysis                                                             */
    /* ------------------------------------------------------------------ */

    private async void on_analyze_clicked () {
        analyze_button.sensitive = false;
        analyze_button.label     = _("Анализируем…");

        var progress_label = new Gtk.Label (_("Подготовка…")) {
            margin_top    = 8,
            margin_bottom = 24,
            margin_start  = 32,
            margin_end    = 32,
            wrap          = true,
            xalign        = 0.5f
        };
        var spinner = new Gtk.Spinner () {
            spinning       = true,
            width_request  = 48,
            height_request = 48,
            margin_top     = 24,
            margin_start   = 48,
            margin_end     = 48
        };
        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        vbox.append (spinner);
        vbox.append (progress_label);

        var dialog = new Adw.Dialog () {
            title = dry_run_btn.active
                ? _("Симуляция анализа")
                : _("Анализ системы"),
            child = vbox
        };
        dialog.present (this);

        /* Forward progress messages to the label */
        ulong sig_id = cleaner.progress.connect ((msg) => {
            progress_label.label = msg;
        });

        current_result = yield cleaner.analyze_async ();

        cleaner.disconnect (sig_id);
        dialog.force_close ();

        analyze_button.sensitive = true;
        analyze_button.label     = dry_run_btn.active
            ? _("Симулировать снова")
            : _("Анализировать снова");

        maybe_send_disk_notification.begin ();
        show_results ();
    }

    /* ------------------------------------------------------------------ */
    /* Disk usage notification                                              */
    /* ------------------------------------------------------------------ */

    private async void maybe_send_disk_notification () {
        var s = AppSettings.get_instance ();
        if (!s.notifications_enabled) return;

        uint64[] usage = yield Utils.get_disk_usage ("/");
        if (usage[0] == 0) return;

        int percent = (int) (usage[1] * 100 / usage[0]);
        if (percent >= s.disk_warning_percent) {
            var notif = new GLib.Notification (
                _("Диск заполнен на %d%%").printf (percent)
            );
            notif.set_body (
                _("Свободно %s — рекомендуется очистка")
                .printf (Utils.format_size (usage[0] - usage[1]))
            );
            notif.set_icon (new GLib.ThemedIcon ("drive-harddisk-symbolic"));
            application.send_notification ("disk-warning", notif);
        }
    }

    /* ------------------------------------------------------------------ */
    /* Results rendering                                                    */
    /* ------------------------------------------------------------------ */

    private void show_results () {
        Gtk.Widget? child = results_box.get_first_child ();
        while (child != null) {
            var next = child.get_next_sibling ();
            results_box.remove (child);
            child = next;
        }

        var r = current_result;

        if (r.total_size == 0) {
            results_box.append (new Adw.StatusPage () {
                title     = _("Мусор не найден"),
                icon_name = "emblem-ok-symbolic"
            });
            main_stack.set_visible_child_name ("results");
            return;
        }

        /* Dry-run banner */
        if (dry_run_btn.active) {
            var banner = new Adw.Banner (_("Режим симуляции — файлы не удалялись"));
            banner.add_css_class ("warning");
            banner.revealed = true;
            results_box.append (banner);
        }

        /* Summary banner */
        var banner = new Adw.Banner (
            _("Найдено %s ненужных данных")
            .printf (Utils.format_size (r.total_size))
        );
        banner.revealed = true;
        results_box.append (banner);

        /* Pie chart */
        results_box.append (build_pie_section (r));

        /* Category cards — system */
        add_card (_("Старые ядра"),        r.old_kernels,      0,  "drive-harddisk-symbolic",            "kernels",    r.kernel_list);
        add_card (_("Flatpak кэш"),         r.flatpak_cache,    1,  "package-x-generic-symbolic",         "flatpak",    null);
        add_card (_("Snap кэш"),            r.snap_cache,       2,  "media-removable-symbolic",           "snap",       null);
        add_card (_("AppImage файлы"),      r.appimages,        3,  "application-x-executable-symbolic",  "appimages",  r.appimage_list);
        add_card (_("Большие архивы"),      r.archives,         4,  "media-optical-symbolic",             "archives",   r.archive_list);
        add_card (_("Системные журналы"),   r.logs,             5,  "folder-documents-symbolic",          "logs",       null);
        add_card (_("Сиротские пакеты"),    r.orphan_packages,  6,  "edit-delete-symbolic",               "orphans",    null);

        /* Category cards — user */
        add_card (_("Корзина"),             r.trash,            7,  "user-trash-symbolic",                "trash",      null);
        add_card (_("Кэш браузеров"),       r.browser_cache,    8,  "web-browser-symbolic",               "browser",    r.browser_dirs);
        add_card (_("Кэш миниатюр"),        r.thumbnails,       9,  "image-x-generic-symbolic",           "thumbnails", null);
        add_card (_("Кэш DNF"),             r.dnf_cache,        10, "system-software-install-symbolic",   "dnf",        null);
        add_card (_("Дублирующиеся файлы"), r.duplicates,       11, "edit-copy-symbolic",                 "duplicates", r.duplicate_list);
        add_card (_("Docker / Podman"),     r.docker_data,      12, "utilities-terminal-symbolic",        "docker",     null);

        /* Re-analyse */
        var re_btn = new Gtk.Button.with_label (
            dry_run_btn.active ? _("Симулировать снова") : _("Анализировать снова")
        ) {
            halign     = Gtk.Align.CENTER,
            margin_top = 8
        };
        re_btn.add_css_class ("pill");
        re_btn.clicked.connect (() => {
            main_stack.set_visible_child_name ("welcome");
            on_analyze_clicked.begin ();
        });
        results_box.append (re_btn);

        main_stack.set_visible_child_name ("results");
    }

    /* ------------------------------------------------------------------ */
    /* Pie chart                                                            */
    /* ------------------------------------------------------------------ */

    private Gtk.Widget build_pie_section (AnalysisResult r) {
        var group = new Adw.PreferencesGroup () {
            title      = _("Распределение мусора"),
            margin_top = 8
        };

        var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 24) {
            halign        = Gtk.Align.CENTER,
            margin_top    = 12,
            margin_bottom = 12
        };

        var da = new Gtk.DrawingArea () {
            content_width  = 220,
            content_height = 220
        };
        da.set_draw_func ((area, cr, w, h) => draw_pie (cr, w, h, r));
        box.append (da);

        string[] labels = {
            _("Ядра"), _("Flatpak"), _("Snap"), _("AppImage"),
            _("Архивы"), _("Журналы"), _("Сироты"),
            _("Корзина"), _("Браузеры"), _("Миниатюры"),
            _("DNF"), _("Дубли"), _("Docker")
        };
        uint64[] values = {
            r.old_kernels, r.flatpak_cache, r.snap_cache, r.appimages,
            r.archives, r.logs, r.orphan_packages,
            r.trash, r.browser_cache, r.thumbnails,
            r.dnf_cache, r.duplicates, r.docker_data
        };

        var legend = new Gtk.Box (Gtk.Orientation.VERTICAL, 4) {
            valign = Gtk.Align.CENTER
        };
        for (int i = 0; i < labels.length; i++) {
            if (values[i] == 0) continue;
            var row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) {
                valign = Gtk.Align.CENTER
            };
            int ci = i;
            var dot = new Gtk.DrawingArea () {
                content_width = 12, content_height = 12,
                valign = Gtk.Align.CENTER
            };
            dot.set_draw_func ((a, cr, w, h) => {
                cr.arc (w / 2.0, h / 2.0, w / 2.0, 0, 2 * Math.PI);
                cr.set_source_rgb (COLORS[ci, 0], COLORS[ci, 1], COLORS[ci, 2]);
                cr.fill ();
            });
            row.append (dot);
            row.append (new Gtk.Label (
                "%s — %s".printf (labels[i], Utils.format_size (values[i]))
            ) { xalign = 0 });
            legend.append (row);
        }
        box.append (legend);

        var clamp = new Adw.Clamp () { child = box, maximum_size = 760 };
        group.add (clamp);
        return group;
    }

    private void draw_pie (Cairo.Context cr, int w, int h, AnalysisResult r) {
        uint64[] values = {
            r.old_kernels, r.flatpak_cache, r.snap_cache, r.appimages,
            r.archives, r.logs, r.orphan_packages,
            r.trash, r.browser_cache, r.thumbnails,
            r.dnf_cache, r.duplicates, r.docker_data
        };
        double total = (double) r.total_size;
        if (total == 0) return;
        double cx = w / 2.0, cy = h / 2.0;
        double radius = double.min (cx, cy) - 4.0;
        double start  = -Math.PI / 2.0;
        for (int i = 0; i < values.length; i++) {
            if (values[i] == 0) continue;
            double sweep = 2.0 * Math.PI * ((double) values[i] / total);
            cr.move_to (cx, cy);
            cr.arc (cx, cy, radius, start, start + sweep);
            cr.close_path ();
            cr.set_source_rgb (COLORS[i, 0], COLORS[i, 1], COLORS[i, 2]);
            cr.fill_preserve ();
            cr.set_source_rgba (0, 0, 0, 0.12);
            cr.set_line_width (1.5);
            cr.stroke ();
            start += sweep;
        }
        cr.arc (cx, cy, radius * 0.44, 0, 2 * Math.PI);
        cr.set_source_rgb (0.13, 0.13, 0.13);
        cr.fill ();
        cr.set_source_rgb (1, 1, 1);
        cr.set_font_size (12);
        string txt = Utils.format_size (r.total_size);
        Cairo.TextExtents ext;
        cr.text_extents (txt, out ext);
        cr.move_to (cx - ext.width / 2.0 - ext.x_bearing,
                    cy - ext.height / 2.0 - ext.y_bearing);
        cr.show_text (txt);
    }

    /* ------------------------------------------------------------------ */
    /* Category card helper                                                 */
    /* ------------------------------------------------------------------ */

    private void add_card (string title, uint64 size, int color_idx,
                            string icon, string category,
                            string[]? files = null) {
        if (size == 0) return;
        var group = new Adw.PreferencesGroup ();

        if (files != null && files.length > 0) {
            var expander = new Adw.ExpanderRow () {
                title    = title,
                subtitle = _("%s · %d элементов").printf (
                               Utils.format_size (size), files.length)
            };
            expander.add_prefix (new Gtk.Image.from_icon_name (icon) { pixel_size = 16 });
            foreach (var f in files) {
                var fr = new Adw.ActionRow () {
                    title          = Path.get_basename (f),
                    subtitle       = Path.get_dirname (f),
                    subtitle_lines = 1
                };
                expander.add_row (fr);
            }
            var btn = new Gtk.Button.with_label (
                dry_run_btn.active ? _("Симулировать") : _("Удалить все")
            ) { valign = Gtk.Align.CENTER };
            btn.add_css_class ("destructive-action");
            btn.add_css_class ("pill");
            btn.clicked.connect (() => confirm_and_clean (category, title, size, files));
            expander.add_suffix (btn);
            group.add (expander);
        } else {
            var row = new Adw.ActionRow () {
                title    = title,
                subtitle = Utils.format_size (size)
            };
            row.add_prefix (new Gtk.Image.from_icon_name (icon) { pixel_size = 16 });
            var btn = new Gtk.Button.with_label (
                dry_run_btn.active ? _("Симулировать") : _("Очистить")
            ) { valign = Gtk.Align.CENTER };
            btn.add_css_class ("destructive-action");
            btn.add_css_class ("pill");
            btn.clicked.connect (() => confirm_and_clean (category, title, size, null));
            row.add_suffix (btn);
            row.activatable_widget = btn;
            group.add (row);
        }
        results_box.append (group);
    }

    /* ------------------------------------------------------------------ */
    /* Confirmation + cleanup                                               */
    /* ------------------------------------------------------------------ */

    private void confirm_and_clean (string category, string title,
                                     uint64 size, string[]? files) {
        string msg = (files != null && files.length > 0)
            ? ngettext (
                "Будет удалён %d элемент (%s). Продолжить?",
                "Будет удалено %d элементов (%s). Продолжить?",
                files.length
              ).printf (files.length, Utils.format_size (size))
            : _("Будет освобождено примерно %s. Продолжить?")
                .printf (Utils.format_size (size));

        string heading = dry_run_btn.active
            ? _("[Симуляция] %s").printf (title)
            : _("Очистить «%s»?").printf (title);

        var dlg = new Adw.AlertDialog (heading, msg);
        dlg.add_response ("cancel", _("Отмена"));
        dlg.add_response ("clean",  dry_run_btn.active ? _("Симулировать") : _("Очистить"));
        dlg.set_response_appearance ("clean", dry_run_btn.active
            ? Adw.ResponseAppearance.SUGGESTED
            : Adw.ResponseAppearance.DESTRUCTIVE);
        dlg.set_default_response ("cancel");
        dlg.set_close_response ("cancel");
        dlg.response.connect ((resp) => {
            if (resp == "clean") perform_cleanup.begin (category, title, size, files);
        });
        dlg.present (this);
    }

    private async void perform_cleanup (string category, string title,
                                         uint64 size, string[]? files) {
        var progress_label = new Gtk.Label (_("Подготовка…")) {
            margin_top    = 8,
            margin_bottom = 24,
            margin_start  = 24,
            margin_end    = 24,
            wrap          = true
        };
        var sp = new Gtk.Spinner () {
            spinning = true, width_request = 40, height_request = 40,
            margin_top = 20, margin_start = 48, margin_end = 48
        };
        var vbox = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);
        vbox.append (sp);
        vbox.append (progress_label);

        var pdlg = new Adw.Dialog () {
            title = dry_run_btn.active ? _("Симуляция…") : _("Очистка…"),
            child = vbox
        };
        pdlg.present (this);

        ulong sid = cleaner.progress.connect ((msg) => { progress_label.label = msg; });
        bool ok = yield cleaner.clean_category (category, files);
        cleaner.disconnect (sid);
        pdlg.force_close ();

        /* Record in history */
        int files_count = (files != null) ? files.length : 0;
        CleanupHistory.get_instance ().append (category, files_count, size, dry_run_btn.active);

        var done = new Adw.AlertDialog (
            ok ? _("Готово") : _("Ошибка"),
            ok ? (dry_run_btn.active
                  ? _("Симуляция завершена. Реальных изменений не произведено.")
                  : _("Очистка выполнена успешно."))
               : _("Не удалось выполнить очистку. Проверьте права доступа.")
        );
        done.add_response ("ok", _("ОК"));
        done.present (this);

        if (ok && !dry_run_btn.active) {
            current_result = yield cleaner.analyze_async ();
            show_results ();
        }
    }

    /* ------------------------------------------------------------------ */
    /* Theme helper                                                         */
    /* ------------------------------------------------------------------ */

    private void apply_color_scheme (string scheme) {
        Adw.ColorScheme cs;
        switch (scheme) {
            case "prefer-dark":  cs = Adw.ColorScheme.PREFER_DARK;  break;
            case "prefer-light": cs = Adw.ColorScheme.PREFER_LIGHT; break;
            default:             cs = Adw.ColorScheme.DEFAULT;       break;
        }
        Adw.StyleManager.get_default ().set_color_scheme (cs);
    }

    /* ------------------------------------------------------------------ */
    /* Settings dialog                                                      */
    /* ------------------------------------------------------------------ */

    private void show_settings_dialog () {
        var s   = AppSettings.get_instance ();
        var dlg = new Adw.PreferencesDialog ();
        dlg.set_title (_("Настройки"));

        /* Page: Analysis */
        var page_analysis = new Adw.PreferencesPage () {
            title     = _("Анализ"),
            icon_name = "system-search-symbolic"
        };

        var grp_scan = new Adw.PreferencesGroup () { title = _("Параметры сканирования") };

        var row_arch = new Adw.SpinRow.with_range (10, 2000, 10) {
            title   = _("Минимальный размер архива"),
            subtitle = _("МБ — архивы меньше этого значения игнорируются")
        };
        row_arch.set_value (s.archive_min_mb);
        row_arch.changed.connect (() => { s.archive_min_mb = (int) row_arch.get_value (); });

        var row_depth = new Adw.SpinRow.with_range (1, 10, 1) {
            title    = _("Глубина поиска"),
            subtitle = _("Максимальная глубина сканирования каталогов")
        };
        row_depth.set_value (s.find_max_depth);
        row_depth.changed.connect (() => { s.find_max_depth = (int) row_depth.get_value (); });

        var row_dupes = new Adw.SpinRow.with_range (1, 500, 1) {
            title    = _("Минимальный размер для дублей"),
            subtitle = _("МБ — файлы меньше этого размера не проверяются на дубли")
        };
        row_dupes.set_value (s.duplicate_min_mb);
        row_dupes.changed.connect (() => { s.duplicate_min_mb = (int) row_dupes.get_value (); });

        grp_scan.add (row_arch);
        grp_scan.add (row_depth);
        grp_scan.add (row_dupes);
        page_analysis.add (grp_scan);

        var grp_journal = new Adw.PreferencesGroup () { title = _("Журналы systemd") };
        var row_journal = new Adw.SpinRow.with_range (1, 365, 1) {
            title    = _("Хранить журналы (дней)"),
            subtitle = _("Записи старше этого срока удаляются при очистке")
        };
        row_journal.set_value (s.journal_retention_days);
        row_journal.changed.connect (() => { s.journal_retention_days = (int) row_journal.get_value (); });
        grp_journal.add (row_journal);
        page_analysis.add (grp_journal);

        /* Page: Notifications */
        var page_notif = new Adw.PreferencesPage () {
            title     = _("Уведомления"),
            icon_name = "preferences-desktop-notifications-symbolic"
        };

        var grp_notif = new Adw.PreferencesGroup () { title = _("Уведомления о диске") };

        var row_notif = new Adw.SwitchRow () {
            title    = _("Включить уведомления"),
            subtitle = _("Показывать уведомление при заполнении диска")
        };
        row_notif.set_active (s.notifications_enabled);
        row_notif.notify["active"].connect (() => {
            s.notifications_enabled = row_notif.get_active ();
        });

        var row_threshold = new Adw.SpinRow.with_range (50, 99, 1) {
            title    = _("Порог заполнения (%)"),
            subtitle = _("Отправлять уведомление когда диск заполнен более чем на X%%")
        };
        row_threshold.set_value (s.disk_warning_percent);
        row_threshold.changed.connect (() => {
            s.disk_warning_percent = (int) row_threshold.get_value ();
        });

        grp_notif.add (row_notif);
        grp_notif.add (row_threshold);
        page_notif.add (grp_notif);

        /* Page: Appearance */
        var page_appear = new Adw.PreferencesPage () {
            title     = _("Внешний вид"),
            icon_name = "preferences-desktop-appearance-symbolic"
        };

        var grp_theme = new Adw.PreferencesGroup () { title = _("Тема оформления") };

        /* Color-scheme drop-down: Auto / Dark / Light */
        string[] theme_strings = { "default", "prefer-dark", "prefer-light" };
        var theme_model = new Gtk.StringList (null);
        theme_model.append (_("Системная (авто)"));
        theme_model.append (_("Тёмная"));
        theme_model.append (_("Светлая"));

        var row_theme = new Adw.ComboRow () {
            title  = _("Цветовая схема"),
            model  = theme_model
        };
        /* Select current */
        string cur_scheme = s.color_scheme;
        for (int i = 0; i < theme_strings.length; i++) {
            if (theme_strings[i] == cur_scheme) { row_theme.selected = i; break; }
        }
        row_theme.notify["selected"].connect (() => {
            string picked = theme_strings[row_theme.selected];
            s.color_scheme = picked;
            apply_color_scheme (picked);
        });
        grp_theme.add (row_theme);
        page_appear.add (grp_theme);

        /* Language drop-down */
        var grp_lang = new Adw.PreferencesGroup () {
            title       = _("Язык интерфейса"),
            description = _("Изменение вступает в силу после перезапуска приложения")
        };

        string[] lang_codes   = { "auto", "en", "ru" };
        var lang_model = new Gtk.StringList (null);
        lang_model.append (_("Системный (авто)"));
        lang_model.append ("English");
        lang_model.append ("Русский");

        var row_lang = new Adw.ComboRow () {
            title = _("Язык"),
            model = lang_model
        };
        string cur_lang = s.language;
        for (int i = 0; i < lang_codes.length; i++) {
            if (lang_codes[i] == cur_lang) { row_lang.selected = i; break; }
        }
        row_lang.notify["selected"].connect (() => {
            s.language = lang_codes[row_lang.selected];

            /* Show restart toast */
            var toast = new Adw.Toast (
                _("Язык изменён — перезапустите приложение")
            ) { timeout = 4 };
            /* Find the nearest ToastOverlay ancestor and add the toast */
            var overlay = find_toast_overlay ();
            if (overlay != null) overlay.add_toast (toast);
        });
        grp_lang.add (row_lang);
        page_appear.add (grp_lang);

        dlg.add (page_analysis);
        dlg.add (page_notif);
        dlg.add (page_appear);
        dlg.present (this);
    }

    private Adw.ToastOverlay? find_toast_overlay () {
        return toast_overlay;
    }

    /* ------------------------------------------------------------------ */
    /* About dialog                                                         */
    /* ------------------------------------------------------------------ */

    private void show_about_dialog () {
        var dlg = new Adw.AboutDialog () {
            application_name    = "Purclean",
            application_icon    = "com.github.byoval.purclean",
            developer_name      = "Byoval Studio",
            version             = APP_VERSION,
            website             = "https://github.com/byoval/purclean",
            issue_url           = "https://github.com/byoval/purclean/issues",
            license_type        = Gtk.License.GPL_3_0,
            copyright           = "© 2026 Byoval Studio",
            /* Translators: one sentence summary shown in About */
            comments            = _("Очистка диска Fedora: ядра, кэш, дубликаты и не только")
        };

        dlg.add_link (_("Исходный код"), "https://github.com/byoval/purclean");

        string[] developers = { "Byoval Studio https://github.com/byoval" };
        dlg.set_developers (developers);

        string[] artists = { "Byoval Studio" };
        dlg.set_artists (artists);

        dlg.present (this);
    }

    /* ------------------------------------------------------------------ */
    /* History dialog                                                       */
    /* ------------------------------------------------------------------ */

    private void show_history_dialog () {
        var entries = CleanupHistory.get_instance ().read_all ();

        var scroll = new Gtk.ScrolledWindow () {
            vexpand           = true,
            hscrollbar_policy = Gtk.PolicyType.NEVER,
            min_content_height = 300,
            max_content_height = 500
        };

        var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0) {
            margin_top    = 8,
            margin_bottom = 8,
            margin_start  = 8,
            margin_end    = 8
        };

        if (entries.length == 0) {
            box.append (new Adw.StatusPage () {
                title       = _("История пуста"),
                description = _("Записи появятся после первой очистки"),
                icon_name   = "document-open-recent-symbolic"
            });
        } else {
            var group = new Adw.PreferencesGroup () { title = _("Последние операции") };
            foreach (var e in entries) {
                string label = e.dry_run
                    ? "[%s] %s".printf (_("Симуляция"), e.category)
                    : e.category;
                var row = new Adw.ActionRow () {
                    title    = label,
                    subtitle = "%s · %s".printf (
                                   e.timestamp,
                                   Utils.format_size (e.freed))
                };
                if (e.dry_run)
                    row.add_prefix (new Gtk.Image.from_icon_name (
                        "media-playback-start-symbolic") { pixel_size = 16 });
                else
                    row.add_prefix (new Gtk.Image.from_icon_name (
                        "edit-delete-symbolic") { pixel_size = 16 });
                group.add (row);
            }
            box.append (group);
        }

        scroll.child = box;

        var dlg = new Adw.Dialog () {
            title            = _("История очисток"),
            child            = scroll,
            content_width    = 480,
            content_height   = 520
        };

        if (entries.length > 0) {
            /* Clear history button */
            var toolbar = new Adw.ToolbarView ();
            var footer  = new Adw.HeaderBar () { show_title = false };
            var clear_btn = new Gtk.Button.with_label (_("Очистить историю"));
            clear_btn.add_css_class ("destructive-action");
            clear_btn.clicked.connect (() => {
                CleanupHistory.get_instance ().clear ();
                dlg.force_close ();
            });
            footer.pack_start (clear_btn);
            toolbar.add_bottom_bar (footer);
            toolbar.set_content (scroll);
            dlg.child = toolbar;
        }

        dlg.present (this);
    }
}
