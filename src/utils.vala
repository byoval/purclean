/*
 * Purclean — Utils
 * Copyright (C) 2026 BYOVAL STUDIO
 *
 * When running inside a Flatpak sandbox, all shell commands are dispatched
 * via `flatpak-spawn --host` so they execute on the real host system.
 */

namespace Purclean.Utils {

    /* Detect if we are running inside a Flatpak container */
    private bool is_flatpak () {
        return FileUtils.test ("/.flatpak-info", FileTest.EXISTS);
    }

    /* Build argv for a shell command, wrapping it with flatpak-spawn when needed */
    private string[] make_argv (string command) {
        if (is_flatpak ()) {
            return { "flatpak-spawn", "--host", "sh", "-c", command };
        }
        return { "sh", "-c", command };
    }

    public async string run_command_async (string command) {
        try {
            var proc = new Subprocess.newv (
                make_argv (command),
                SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_SILENCE
            );
            Bytes? stdout_bytes = null;
            yield proc.communicate_async (null, null, out stdout_bytes, null);

            if (stdout_bytes != null && stdout_bytes.get_size () > 0) {
                unowned uint8[]? data = stdout_bytes.get_data ();
                if (data != null) {
                    string s = (string) data;
                    if (s != null) return s.strip ();
                }
            }
        } catch (Error e) {
            warning ("run_command_async: %s", e.message);
        }
        return "";
    }

    public async bool run_pkexec_command (string command) {
        /* Inside Flatpak we call pkexec on the host via flatpak-spawn */
        string[] argv;
        if (is_flatpak ()) {
            argv = { "flatpak-spawn", "--host", "pkexec", "sh", "-c", command };
        } else {
            string escaped  = command.replace ("\"", "\\\"");
            string full_cmd = "pkexec sh -c \"%s\"".printf (escaped);
            argv = { "sh", "-c", full_cmd };
        }

        try {
            var proc = new Subprocess.newv (argv, SubprocessFlags.NONE);
            yield proc.wait_async (null);
            return proc.get_exit_status () == 0;
        } catch (Error e) {
            warning ("run_pkexec_command: %s", e.message);
            return false;
        }
    }

    public async uint64 get_directory_size (string path) {
        string out_str = yield run_command_async (
            "du -sb \"%s\" 2>/dev/null | cut -f1".printf (path)
        );
        if (out_str == "") return 0;
        return uint64.parse (out_str.strip ());
    }

    public async uint64 get_file_size (string path) {
        string out_str = yield run_command_async (
            "stat -c %%s \"%s\" 2>/dev/null".printf (path)
        );
        if (out_str == "") return 0;
        return uint64.parse (out_str.strip ());
    }

    public async uint64[] get_disk_usage (string path = "/") {
        string out_str = yield run_command_async (
            "df -B1 --output=size,used \"%s\" 2>/dev/null | tail -1".printf (path)
        );
        if (out_str == "") return { 0, 0 };
        string[] parts = out_str.strip ().split_set (" \t", 2);
        if (parts.length < 2) return { 0, 0 };
        return { uint64.parse (parts[0].strip ()), uint64.parse (parts[1].strip ()) };
    }

    public uint64 parse_human_size (string? text) {
        if (text == null || text.strip () == "") return 0;
        string t = text.strip ().up ();
        if (t.contains ("G")) return (uint64) (double.parse (t) * 1024 * 1024 * 1024);
        if (t.contains ("M")) return (uint64) (double.parse (t) * 1024 * 1024);
        if (t.contains ("K")) return (uint64) (double.parse (t) * 1024);
        return uint64.parse (t);
    }

    public string format_size (uint64 bytes) {
        return GLib.format_size (bytes);
    }
}
