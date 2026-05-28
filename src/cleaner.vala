/*
 * Purclean — Cleaner
 * Copyright (C) 2026 BYOVAL STUDIO
 */

public struct Purclean.AnalysisResult {
    /* sizes in bytes */
    public uint64 total_size;
    public uint64 old_kernels;
    public uint64 flatpak_cache;
    public uint64 snap_cache;
    public uint64 appimages;
    public uint64 logs;
    public uint64 archives;
    public uint64 orphan_packages;
    public uint64 trash;
    public uint64 browser_cache;
    public uint64 thumbnails;
    public uint64 dnf_cache;
    public uint64 duplicates;
    public uint64 docker_data;

    /* file/item lists */
    public string[] kernel_list;
    public string[] appimage_list;
    public string[] archive_list;
    public string[] duplicate_list;   /* pairs: hash\npath\npath... separated by empty line */
    public string[] browser_dirs;     /* which browser cache dirs exist */
}

/* Returned by async file-search methods to avoid out-params in async. */
private class Purclean.FileListResult : Object {
    public uint64   size  = 0;
    public string[] files = {};
}

public class Purclean.Cleaner : Object {

    /* Emitted during analysis/cleanup so the UI can show progress text */
    public signal void progress (string message);

    /* When true, clean_category does nothing (simulates only) */
    public bool dry_run { get; set; default = false; }

    /* ------------------------------------------------------------------ */
    /* Full analysis                                                        */
    /* ------------------------------------------------------------------ */

    public async AnalysisResult analyze_async () {
        var s  = AppSettings.get_instance ();
        var r  = AnalysisResult ();

        progress (_("Поиск старых ядер…"));
        var kernels      = yield get_old_kernels_real ();
        r.old_kernels    = kernels.size;
        r.kernel_list    = kernels.files;

        progress (_("Анализ кэша Flatpak…"));
        r.flatpak_cache  = yield Utils.get_directory_size ("/var/tmp/flatpak-cache");

        progress (_("Анализ кэша Snap…"));
        r.snap_cache     = yield Utils.get_directory_size ("/var/snap");

        progress (_("Поиск AppImage файлов…"));
        var appimg       = yield find_large_files (
            Environment.get_home_dir (), "*.AppImage", 10,
            s.find_max_depth
        );
        r.appimages      = appimg.size;
        r.appimage_list  = appimg.files;

        progress (_("Поиск больших архивов…"));
        var arch         = yield find_large_files (
            Path.build_filename (Environment.get_home_dir (), "Downloads"),
            "*.iso *.tar.gz *.tar.xz *.tar.bz2 *.zip *.7z *.rar",
            s.archive_min_mb, s.find_max_depth
        );
        r.archives       = arch.size;
        r.archive_list   = arch.files;

        progress (_("Анализ журналов systemd…"));
        r.logs           = yield get_journal_size ();

        progress (_("Поиск сиротских пакетов…"));
        r.orphan_packages = yield get_orphan_size_real ();

        progress (_("Анализ корзины…"));
        r.trash          = yield Utils.get_directory_size (
            Path.build_filename (Environment.get_user_data_dir (), "Trash")
        );

        progress (_("Анализ кэша браузеров…"));
        var browser      = yield get_browser_cache ();
        r.browser_cache  = browser.size;
        r.browser_dirs   = browser.files;

        progress (_("Анализ кэша миниатюр…"));
        r.thumbnails     = yield Utils.get_directory_size (
            Path.build_filename (Environment.get_user_cache_dir (), "thumbnails")
        );

        progress (_("Анализ кэша DNF…"));
        r.dnf_cache      = yield Utils.get_directory_size ("/var/cache/dnf");

        progress (_("Поиск файлов Docker/Podman…"));
        r.docker_data    = yield get_docker_size ();

        progress (_("Поиск дублирующихся файлов…"));
        var dupes        = yield find_duplicates (s.duplicate_min_mb);
        r.duplicates     = dupes.size;
        r.duplicate_list = dupes.files;

        r.total_size =
            r.old_kernels    + r.flatpak_cache + r.snap_cache  +
            r.appimages      + r.archives      + r.logs        +
            r.orphan_packages + r.trash        + r.browser_cache +
            r.thumbnails     + r.dnf_cache     + r.docker_data  +
            r.duplicates;

        return r;
    }

    /* ------------------------------------------------------------------ */
    /* Real kernel size via rpm -qi                                         */
    /* ------------------------------------------------------------------ */

    private async FileListResult get_old_kernels_real () {
        var r = new FileListResult ();

        /* List removable kernel packages */
        string pkgs = yield Utils.run_command_async (
            "dnf repoquery --installonly --latest-limit=-2 -q 2>/dev/null"
        );
        if (pkgs == "") return r;

        foreach (var line in pkgs.split ("\n")) {
            string p = line.strip ();
            if (p == "") continue;
            r.files += p;

            /* Real installed size from rpm */
            string sz = yield Utils.run_command_async (
                "rpm -qi \"%s\" 2>/dev/null | awk '/^Size/{print $3}'".printf (p)
            );
            r.size += uint64.parse (sz.strip ());
        }

        /* Fallback: 650 MB per kernel if rpm gave nothing */
        if (r.size == 0)
            r.size = (uint64) r.files.length * 650 * 1024 * 1024;

        return r;
    }

    /* ------------------------------------------------------------------ */
    /* Real orphan size via dnf info                                        */
    /* ------------------------------------------------------------------ */

    private async uint64 get_orphan_size_real () {
        string total_str = yield Utils.run_command_async (
            "dnf list autoremove -q 2>/dev/null | tail -n +2 | " +
            "awk '{print $1}' | " +
            "xargs -r rpm -qi 2>/dev/null | " +
            "awk '/^Size/{s+=$3} END{print s}'"
        );
        uint64 total = uint64.parse (total_str.strip ());
        /* Fallback: 8 MB per package */
        if (total == 0) {
            string count_str = yield Utils.run_command_async (
                "dnf list autoremove -q 2>/dev/null | tail -n +2 | wc -l"
            );
            total = uint64.parse (count_str.strip ()) * 8 * 1024 * 1024;
        }
        return total;
    }

    /* ------------------------------------------------------------------ */
    /* Find large files matching mask                                       */
    /* ------------------------------------------------------------------ */

    private async FileListResult find_large_files (string dir, string mask,
                                                    int min_mb, int max_depth) {
        var r = new FileListResult ();

        string[] parts = mask.split (" ");
        var expr = new StringBuilder ();
        for (int i = 0; i < parts.length; i++) {
            if (i > 0) expr.append (" -o ");
            expr.append_printf ("-name \"%s\"", parts[i]);
        }

        string cmd =
            "find \"%s\" -maxdepth %d -type f \\( %s \\) -size +%dM 2>/dev/null"
            .printf (dir, max_depth, expr.str, min_mb);

        string output = yield Utils.run_command_async (cmd);
        foreach (var file in output.split ("\n")) {
            string f = file.strip ();
            if (f == "") continue;
            r.files += f;
            r.size  += yield Utils.get_file_size (f);
        }
        return r;
    }

    /* ------------------------------------------------------------------ */
    /* Journal size                                                         */
    /* ------------------------------------------------------------------ */

    private async uint64 get_journal_size () {
        string output = yield Utils.run_command_async (
            "journalctl --disk-usage 2>/dev/null"
        );
        foreach (var token in output.split (" ")) {
            uint64 parsed = Utils.parse_human_size (token);
            if (parsed > 0) return parsed;
        }
        return 0;
    }

    /* ------------------------------------------------------------------ */
    /* Browser caches                                                       */
    /* ------------------------------------------------------------------ */

    private async FileListResult get_browser_cache () {
        var r = new FileListResult ();
        string cache = Environment.get_user_cache_dir ();
        string[] dirs = {
            Path.build_filename (cache, "google-chrome"),
            Path.build_filename (cache, "chromium"),
            Path.build_filename (cache, "BraveSoftware"),
            Path.build_filename (cache, "vivaldi"),
            Path.build_filename (Environment.get_home_dir (), ".mozilla", "firefox"),
            Path.build_filename (cache, "mozilla"),
        };
        foreach (var d in dirs) {
            if (FileUtils.test (d, FileTest.IS_DIR)) {
                uint64 sz = yield Utils.get_directory_size (d);
                if (sz > 0) {
                    r.files += d;
                    r.size  += sz;
                }
            }
        }
        return r;
    }

    /* ------------------------------------------------------------------ */
    /* Docker / Podman                                                      */
    /* ------------------------------------------------------------------ */

    private async uint64 get_docker_size () {
        /* Podman */
        string podman = yield Utils.run_command_async (
            "podman system df --format '{{.Size}}' 2>/dev/null | tail -1"
        );
        if (podman != "") {
            uint64 sz = Utils.parse_human_size (podman);
            if (sz > 0) return sz;
        }
        /* Docker */
        string docker = yield Utils.run_command_async (
            "docker system df --format '{{.Size}}' 2>/dev/null | awk '{s+=$1} END{print s}'"
        );
        return Utils.parse_human_size (docker);
    }

    /* ------------------------------------------------------------------ */
    /* Duplicate file detection via sha256sum                              */
    /* ------------------------------------------------------------------ */

    private async FileListResult find_duplicates (int min_mb) {
        var r = new FileListResult ();

        string home = Environment.get_home_dir ();
        /* Only scan common user dirs to stay fast */
        string cmd =
            "find \"%s/Documents\" \"%s/Downloads\" \"%s/Pictures\" \"%s/Videos\" "
            .printf (home, home, home, home) +
            "-type f -size +%dM 2>/dev/null | ".printf (min_mb) +
            "xargs sha256sum 2>/dev/null | sort | " +
            "awk 'BEGIN{ph=\"\"} {h=$1; $1=\"\"; f=$0; " +
            "if(h==ph){if(!started){print prev_f; started=1} print f} " +
            "else{started=0} ph=h; prev_f=f}'";

        string output = yield Utils.run_command_async (cmd);
        uint64 total = 0;
        foreach (var line in output.split ("\n")) {
            string f = line.strip ();
            if (f == "") continue;
            r.files += f;
            total   += yield Utils.get_file_size (f);
        }
        /* Wasted space = half of total (keep one copy of each) */
        r.size = total / 2;
        return r;
    }

    /* ------------------------------------------------------------------ */
    /* Cleanup                                                             */
    /* ------------------------------------------------------------------ */

    public async bool clean_category (string category, string[]? file_list = null) {
        var s = AppSettings.get_instance ();

        if (dry_run) {
            progress (_("[Симуляция] %s — ничего не удаляется").printf (category));
            yield Utils.run_command_async ("sleep 0.3");
            return true;
        }

        switch (category) {
            case "kernels":
                progress (_("Удаление старых ядер…"));
                return yield Utils.run_pkexec_command (
                    "dnf remove --oldinstallonly --setopt=installonly_limit=2 -y"
                );

            case "flatpak":
                progress (_("Очистка кэша Flatpak…"));
                yield Utils.run_command_async (
                    "flatpak uninstall --unused -y 2>/dev/null; " +
                    "rm -rf ~/.cache/flatpak/oci 2>/dev/null; " +
                    "rm -rf /var/tmp/flatpak-cache/* 2>/dev/null"
                );
                return true;

            case "snap":
                progress (_("Удаление отключённых версий Snap…"));
                yield Utils.run_command_async (
                    "snap list --all 2>/dev/null | " +
                    "awk '/disabled/{print $1, $3}' | " +
                    "while read n r; do snap remove \"$n\" --revision=\"$r\"; done"
                );
                return true;

            case "appimages":
            case "archives":
            case "duplicates":
                if (file_list != null) {
                    foreach (var f in file_list) {
                        progress (_("Удаление %s").printf (Path.get_basename (f)));
                        yield Utils.run_command_async ("rm -f \"%s\"".printf (f));
                    }
                }
                return true;

            case "logs":
                progress (_("Очистка журналов systemd…"));
                return yield Utils.run_pkexec_command (
                    "journalctl --vacuum-time=%dd --vacuum-size=500M"
                    .printf (s.journal_retention_days)
                );

            case "orphans":
                progress (_("Удаление сиротских пакетов…"));
                return yield Utils.run_pkexec_command ("dnf autoremove -y");

            case "trash":
                progress (_("Очистка корзины…"));
                yield Utils.run_command_async (
                    "rm -rf \"%s/Trash/files\"/* \"%s/Trash/info\"/* 2>/dev/null"
                    .printf (
                        Environment.get_user_data_dir (),
                        Environment.get_user_data_dir ()
                    )
                );
                return true;

            case "browser":
                progress (_("Очистка кэша браузеров…"));
                if (file_list != null) {
                    foreach (var d in file_list) {
                        progress (_("Очистка %s").printf (Path.get_basename (d)));
                        yield Utils.run_command_async (
                            "rm -rf \"%s/Cache\"/* \"%s/cache\"/* 2>/dev/null"
                            .printf (d, d)
                        );
                    }
                }
                return true;

            case "thumbnails":
                progress (_("Удаление кэша миниатюр…"));
                yield Utils.run_command_async (
                    "rm -rf \"%s/thumbnails\"/* 2>/dev/null"
                    .printf (Environment.get_user_cache_dir ())
                );
                return true;

            case "dnf":
                progress (_("Очистка кэша DNF…"));
                return yield Utils.run_pkexec_command ("dnf clean all");

            case "docker":
                progress (_("Очистка неиспользуемых образов Docker/Podman…"));
                yield Utils.run_command_async (
                    "podman system prune -f 2>/dev/null || docker system prune -f 2>/dev/null"
                );
                return true;

            default:
                return false;
        }
    }
}
