/*
* Copyright (c) {2021} torikulhabib (https://github.com/gabutakut)
*
* This program is free software; you can redistribute it and/or
* modify it under the terms of the GNU General Public
* License as published by the Free Software Foundation; either
* version 2 of the License, or (at your option) any later version.
*
* This program is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
* General Public License for more details.
*
* You should have received a copy of the GNU General Public
* License along with this program; if not, write to the
* Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
* Boston, MA 02110-1301 USA
*
* Authored by: torikulhabib <torik.habib@Gmail.com>
*/

namespace Gabut {
    public class GabutApp : Gtk.Application {
        public static GabutWindow gabutwindow = null;
        public static Sqlite.Database db;
        private Gdk.Clipboard clipboard;
        public GLib.List<Downloader> downloaders;
        public GLib.List<SuccesDialog> succesdls;
        private bool startingup = false;
        private bool dontopen = false;

        public GabutApp () {
            Object (
                application_id: "com.github.gabutakut.gabutdm",
                flags: ApplicationFlags.HANDLES_COMMAND_LINE
            );
        }

        construct {
            GLib.OptionEntry [] options = new GLib.OptionEntry [3];
            options [0] = { "startingup", 's', 0, OptionArg.NONE, null, null, "Run App on Startup" };
            options [1] = { GLib.OPTION_REMAINING, 0, 0, OptionArg.FILENAME_ARRAY, null, null, "Open File or URIs" };
            options [2] = { null };
            add_main_option_entries (options);
        }

        public override int command_line (ApplicationCommandLine command) {
            var dict = command.get_options_dict ();
            if (dict.contains ("startingup") && gabutwindow == null) {
                startingup = true;
            }
            create_startup.begin ();
            if (dict.contains (GLib.OPTION_REMAINING)) {
                foreach (string arg_file in dict.lookup_value (GLib.OPTION_REMAINING, VariantType.BYTESTRING_ARRAY).get_bytestring_array ()) {
                    if (GLib.FileUtils.test (arg_file, GLib.FileTest.EXISTS)) {
                        dialog_url (File.new_for_path (arg_file).get_uri ());
                    } else {
                        dialog_url (arg_file);
                    }
                }
                if (gabutwindow != null) {
                    return Posix.EXIT_SUCCESS;
                } else {
                    dontopen = true;
                }
            }
            activate ();
            return Posix.EXIT_SUCCESS;
        }

        protected override void activate () {
            if (gabutwindow == null) {
                if (open_database (out db) != Sqlite.OK) {
                    notify_app (_("Database Error"),
                                _("Can't open database: %s\n").printf (db.errmsg ()), new ThemedIcon ("office-database"));
                }
                settings_table ();
                if (!bool.parse (get_dbsetting (DBSettings.STARTUP)) && startingup) {
                    return;
                }
                exec_aria ();
                if (!GLib.FileUtils.test (create_folder (".bootstrap.min.css"), GLib.FileTest.EXISTS)) {
                    get_css_online.begin ("https://maxcdn.bootstrapcdn.com/bootstrap/3.4.1/css/bootstrap.min.css", create_folder (".bootstrap.min.css"));
                }
                if (!GLib.FileUtils.test (create_folder (".dropzone.min.js"), GLib.FileTest.EXISTS)) {
                    get_css_online.begin ("https://unpkg.com/dropzone@5/dist/min/dropzone.min.js", create_folder (".dropzone.min.js"));
                }
                if (!GLib.FileUtils.test (create_folder (".dropzone.min.css"), GLib.FileTest.EXISTS)) {
                    get_css_online.begin ("https://unpkg.com/dropzone@5/dist/min/dropzone.min.css", create_folder (".dropzone.min.css"));
                }
                var gabutserver = new GabutServer ();
                gabutserver.set_listent.begin (int.parse (get_dbsetting (DBSettings.PORTLOCAL)));
                gabutserver.send_post_data.connect (dialog_server);
                gabutwindow = new GabutWindow (this);

                var droptarget = new Gtk.DropTarget (Type.STRING, Gdk.DragAction.COPY);
                gabutwindow.child.add_controller (droptarget);
                droptarget.on_drop.connect (on_drag_data_received);

                gabutwindow.send_file.connect (dialog_url);
                gabutwindow.stop_server.connect (()=> {
                    gabutserver.stop_server ();
                });
                gabutwindow.get_host.connect ((reboot)=> {
                    if (reboot) {
                        gabutserver.stop_server ();
                        gabutserver.set_listent.begin (int.parse (get_dbsetting (DBSettings.PORTLOCAL)));
                    }
                    return gabutserver.get_address ();
                });
                gabutwindow.restart_server.connect (()=> {
                    gabutserver.stop_server ();
                    gabutserver.set_listent.begin (int.parse (get_dbsetting (DBSettings.PORTLOCAL)));
                });
                gabutserver.address_url.connect ((url, options, later, linkmode)=> {
                    gabutwindow.add_url_box (url, options, later, linkmode);
                });
                downloaders = new GLib.List<Downloader> ();
                succesdls = new GLib.List<SuccesDialog> ();
                var action_download = new SimpleAction ("downloader", VariantType.STRING);
                action_download.activate.connect ((parameter) => {
                    string aria_gid = parameter.get_string (null);
                    if (!dialog_active (aria_gid)) {
                        download (aria_gid);
                    }
                });
                add_action (action_download);
                var action_status = new SimpleAction ("status", VariantType.STRING);
                action_status.activate.connect ((parameter) => {
                    string aria_gid = parameter.get_string (null);
                    gabutwindow.fast_respond (aria_gid);
                });
                add_action (action_status);
                var action_succes = new SimpleAction ("succes", VariantType.STRING);
                action_succes.activate.connect ((parameter) => {
                    string succes = parameter.get_string (null);
                    if (!succes_active (succes)) {
                        dialog_succes (succes);
                    }
                });
                add_action (action_succes);
                var close_dialog = new SimpleAction ("destroy", VariantType.STRING);
                close_dialog.activate.connect ((parameter) => {
                    string aria_gid = parameter.get_string (null);
                    destroy_active (aria_gid);
                });
                add_action (close_dialog);
                gabutserver.get_dl_row.connect ((status)=> {
                    return gabutwindow.get_dl_row (status);
                });
                clipboard = gabutwindow.get_display ().get_clipboard ();
                clipboard.changed.connect (on_clipboard);
                pantheon_theme.begin ();
                gabutwindow.load_dowanload ();
                download_table ();
                if (!startingup && !dontopen) {
                    gabutwindow.show ();
                }
            } else {
                if (startingup) {
                    gabutwindow.show ();
                    startingup = false;
                } else {
                    gabutwindow.present ();
                }
            }
        }

        private bool succes_active (string datastr) {
            bool active = false;
            succesdls.foreach ((succesdl)=> {
                if (succesdl.datastr.split ("<gabut>")[1] == datastr.split ("<gabut>")[1]) {
                    succesdl.present ();
                    active = true;
                }
            });
            return active;
        }

        private void destroy_active (string ariagid) {
            downloaders.foreach ((downloader)=> {
                if (downloader.ariagid == ariagid) {
                    downloaders.remove_link (downloaders.find (downloader));
                    remove_window (downloader);
                    downloader.destroy ();
                }
            });
        }

        public void dialog_succes (string strdata) {
            var succesdl = new SuccesDialog (this);
            succesdl.show ();
            succesdl.set_dialog (strdata);
            succesdls.append (succesdl);
            succesdl.close.connect (()=> {
                succesdls.foreach ((succes)=> {
                    if (succes == succesdl) {
                        succesdls.remove_link (succesdls.find (succes));
                        remove_window (succes);
                    }
                });
            });
        }

        public void dialog_server (MatchInfo match_info) {
            var addurl = new AddUrl (this);
            addurl.server_link (match_info);
            addurl.show ();
            addurl.downloadfile.connect ((url, options, later, linkmode)=> {
                gabutwindow.add_url_box (url, options, later, linkmode);
            });
            addurl.close.connect (()=> {
                backupclip = null;
            });
        }

        public void dialog_url (string link) {
            string icon = "";
            if (link.has_prefix ("http://") || link.has_prefix ("https://") || link.has_prefix ("ftp://") || link.has_prefix ("sftp://")) {
                icon = "insert-link";
            } else if (link.has_prefix ("magnet:?")) {
                icon = "com.github.gabutakut.gabutdm.magnet";
                link.replace ("tr.N=", "tr=");
            } else if (link.has_suffix (".torrent")) {
                icon = "application-x-bittorrent";
            } else if (link.has_suffix (".metalink")) {
                icon = "com.github.gabutakut.gabutdm";
            } else if (link == "") {
                icon = "list-add";
            } else {
                return;
            }
            var addurl = new AddUrl (this);
            addurl.add_link (link, icon);
            addurl.show ();
            addurl.downloadfile.connect ((url, options, later, linkmode)=> {
                gabutwindow.add_url_box (url, options, later, linkmode);
            });
            addurl.close.connect (()=> {
                backupclip = null;
            });
        }

        private bool dialog_active (string ariagid) {
            bool active = false;
            downloaders.foreach ((downloader)=> {
                if (downloader.ariagid == ariagid) {
                    downloader.present ();
                    active = true;
                }
            });
            return active;
        }

        private void download (string aria_gid) {
            var downloader = new Downloader (this);
            downloader.aria_gid (aria_gid);
            downloader.show ();
            downloaders.append (downloader);
            downloader.close.connect (()=> {
                downloaders.foreach ((download)=> {
                    if (download == downloader) {
                        downloaders.remove_link (downloaders.find (download));
                        remove_window (download);
                    }
                });
            });
            downloader.sendselected.connect ((ariagid, selected)=> {
                return gabutwindow.set_selected (ariagid, selected);
            });
        }

        private string? textclip = "";
        private string? backupclip = "";
        private void on_clipboard () {
            get_value.begin (()=> {
                if (textclip != null && textclip != "") {
                    string strstrip = textclip.strip ();
                    if (backupclip != strstrip) {
                        dialog_url (strstrip);
                        backupclip = strstrip;
                    }
                }
            });
        }

        private async void get_value () throws Error {
            unowned GLib.Value? value = yield clipboard.read_value_async (GLib.Type.STRING, GLib.Priority.DEFAULT, null);
            textclip = value.get_string ();
        }

        private bool on_drag_data_received (GLib.Value value, double x, double y) {
            if (value.get_string ().contains ("\n")) {
                foreach (string url in value.get_string ().strip ().split ("\n")) {
                    dialog_url (url.strip ());
                }
            } else {
                dialog_url (value.get_string ().strip ());
            }
            return Gdk.EVENT_PROPAGATE;
        }

        public static int main (string[] args) {
            var app = new GabutApp ();
            return app.run (args);
        }
    }
}
