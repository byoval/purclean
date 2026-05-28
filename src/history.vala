/*
 * Purclean — CleanupHistory
 * Copyright (C) 2026 BYOVAL STUDIO
 *
 * Simple append-only log stored at
 *   ~/.local/share/purclean/history.log
 * Each line: ISO-timestamp|category|files_count|bytes_freed|dry_run
 */

public struct Purclean.HistoryEntry {
    public string timestamp;
    public string category;
    public int    files;
    public uint64 freed;
    public bool   dry_run;
}

public class Purclean.CleanupHistory : Object {

    private static CleanupHistory? _instance = null;
    private string _log_path;

    public static CleanupHistory get_instance () {
        if (_instance == null) _instance = new CleanupHistory ();
        return _instance;
    }

    private CleanupHistory () {
        string data_dir = Path.build_filename (
            Environment.get_user_data_dir (), "purclean"
        );
        try {
            File.new_for_path (data_dir).make_directory_with_parents (null);
        } catch (Error e) {
            /* already exists — ignore */
        }
        _log_path = Path.build_filename (data_dir, "history.log");
    }

    /* Append one entry */
    public void append (string category, int files, uint64 freed, bool dry_run) {
        var now = new DateTime.now_local ();
        string line = "%s|%s|%d|%llu|%s\n".printf (
            now.format ("%Y-%m-%dT%H:%M:%S"),
            category, files, freed,
            dry_run ? "true" : "false"
        );
        try {
            var f = File.new_for_path (_log_path);
            FileOutputStream stream;
            if (f.query_exists ()) {
                stream = f.append_to (FileCreateFlags.NONE);
            } else {
                stream = f.create (FileCreateFlags.NONE);
            }
            stream.write (line.data);
            stream.close ();
        } catch (Error e) {
            warning ("history append error: %s", e.message);
        }
    }

    /* Read all entries (most recent first) */
    public HistoryEntry[] read_all () {
        HistoryEntry[] result = {};
        try {
            var f = File.new_for_path (_log_path);
            if (!f.query_exists ()) return result;

            var input   = new DataInputStream (f.read ());
            string? line;
            while ((line = input.read_line ()) != null) {
                string[] parts = line.split ("|");
                if (parts.length < 5) continue;
                HistoryEntry e = {
                    timestamp: parts[0],
                    category:  parts[1],
                    files:     int.parse (parts[2]),
                    freed:     uint64.parse (parts[3]),
                    dry_run:   parts[4] == "true"
                };
                result += e;
            }
        } catch (Error e) {
            warning ("history read error: %s", e.message);
        }

        /* Reverse so newest is first */
        for (int i = 0, j = result.length - 1; i < j; i++, j--) {
            HistoryEntry tmp = result[i];
            result[i] = result[j];
            result[j] = tmp;
        }
        return result;
    }

    /* Clear the log file */
    public void clear () {
        try {
            File.new_for_path (_log_path).delete ();
        } catch (Error e) {
            warning ("history clear error: %s", e.message);
        }
    }
}
