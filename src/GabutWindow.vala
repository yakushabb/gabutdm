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
    public class GabutWindow : Gtk.ApplicationWindow {
        public signal void send_file (string url);
        public signal void stop_server ();
        public signal void restart_server ();
        public signal string get_host (bool reboot);
        private Gtk.ListBox list_box;
        private Gtk.Stack headerstack;
        private Gtk.Revealer property_rev;
        private Preferences preferences = null;
        private QrCode qrcode;
        private Gtk.SearchEntry search_entry;
        private ModeButton view_mode;
        private AlertView nodown_alert;
        private GLib.List<AddUrl> properties;
        private DbusmenuItem menudbus;
        private DbusmenuItem openmenu;
        private DbusmenuItem startmenu;
        private DbusmenuItem pausemenu;
        private CanonicalDbusmenu dbusserver;
        private int64 globalactive = 0;
        private GLib.List<DownloadRow> listrow;

        public GabutWindow (Gtk.Application application) {
            Object (application: application);
        }

        construct {
            dbusserver = new CanonicalDbusmenu ();
            openmenu = new DbusmenuItem ();
            openmenu.property_set (MenuItem.LABEL.get_name (), _("Gabut Download Manager"));
            openmenu.property_set (MenuItem.ICON_NAME.get_name (), "com.github.gabutakut.gabutdm");
            openmenu.property_set_bool (MenuItem.VISIBLE.get_name (), true);
            openmenu.item_activated.connect (present);

            startmenu = new DbusmenuItem ();
            startmenu.property_set (MenuItem.LABEL.get_name (), _("Start All"));
            startmenu.property_set (MenuItem.ICON_NAME.get_name (), "media-playback-start");
            startmenu.property_set_bool (MenuItem.VISIBLE.get_name (), true);
            startmenu.item_activated.connect (start_all);

            pausemenu = new DbusmenuItem ();
            pausemenu.property_set (MenuItem.LABEL.get_name (), _("Pause All"));
            pausemenu.property_set (MenuItem.ICON_NAME.get_name (), "media-playback-pause");
            pausemenu.property_set_bool (MenuItem.VISIBLE.get_name (), true);
            pausemenu.item_activated.connect (stop_all);
            menudbus = new DbusmenuItem ();
            append_dbus.begin (startmenu);
            append_dbus.begin (pausemenu);

            nodown_alert = new AlertView (
                _("No File Download"),
                _("insert Link, open file or Drag and Drop Torrent, Metalink, Magnet URIs."),
                "com.github.gabutakut.gabutdm"
            );
            nodown_alert.show ();
            listrow = new GLib.List<DownloadRow> ();
            list_box = new Gtk.ListBox () {
                activate_on_single_click = true,
                selection_mode = Gtk.SelectionMode.BROWSE
            };
            list_box.set_placeholder (nodown_alert);

            var scrolled = new Gtk.ScrolledWindow () {
                height_request = 350,
                width_request = 650,
                vexpand = true
            };
            scrolled.set_child (list_box);

            headerstack = new Gtk.Stack () {
                transition_type = Gtk.StackTransitionType.SLIDE_DOWN,
                transition_duration = 500,
                hhomogeneous = false
            };
            headerstack.add_named (mode_headerbar (), "mode");
            headerstack.add_named (saarch_headerbar (), "search");
            headerstack.visible_child_name = "mode";
            headerstack.show ();

            set_titlebar (build_headerbar ());

            var mainwindow = new Gtk.Grid () {
                orientation = Gtk.Orientation.VERTICAL
            };
            mainwindow.attach (headerstack, 0, 0);
            mainwindow.attach (scrolled, 0, 1);
            set_child (mainwindow);
            notify["is-active"].connect (()=> {
                set_badge.begin (globalactive);
            });
            hide_on_close = bool.parse (get_dbsetting (DBSettings.ONBACKGROUND));
            close_request.connect (() => {
                if (bool.parse (get_dbsetting (DBSettings.ONBACKGROUND))) {
                    append_dbus.begin (openmenu);
                    menudbus.child_reorder (openmenu, 1);
                    return false;
                } else {
                    save_all_download ();
                    return false;
                }
            });
            Timeout.add (500, set_menulauncher);
        }

        private bool set_menulauncher () {
            globalactive = int64.parse (aria_globalstat (GlobalStat.NUMACTIVE));
            bool statact = globalactive > 0;
            set_progress_visible.begin (!is_active && statact);
            set_badge_visible.begin (!is_active && statact);
            return true;
        }

        private Gtk.HeaderBar build_headerbar () {
            var tittle = new Gtk.Label ("Gabut Download Manager") {
                wrap_mode = Pango.WrapMode.WORD_CHAR,
                xalign = 0,
                attributes = set_attribute (Pango.Weight.BOLD)
            };
            var headerbar = new Gtk.HeaderBar () {
                title_widget = tittle,
                hexpand = true,
                decoration_layout = "close:maximize"
            };
            var menu_button = new Gtk.Button.from_icon_name ("open-menu") {
                tooltip_text = _("Open Settings")
            };
            headerbar.pack_end (menu_button);
            menu_button.clicked.connect (()=> {
                if (preferences == null && aria_getverion ()) {
                    preferences = new Preferences (application);
                    preferences.set_transient_for (this);
                    preferences.show ();
                    preferences.restart_server.connect (()=> {
                        restart_server ();
                    });
                    preferences.restart_process.connect (()=> {
                        foreach (var row in list_box.get_selected_rows ()) {
                            ((DownloadRow) row).if_not_exist (((DownloadRow) row).ariagid, ((DownloadRow) row).linkmode, ((DownloadRow) row).status);
                        }
                    });
                    preferences.max_active.connect (()=> {
                        next_download ();
                    });
                    preferences.close.connect (()=> {
                        if (bool.parse (get_dbsetting (DBSettings.ONBACKGROUND)) != hide_on_close) {
                            hide_on_close = bool.parse (get_dbsetting (DBSettings.ONBACKGROUND));
                        }
                        preferences = null;
                    });
                }
            });

            var search_button = new Gtk.Button.from_icon_name ("system-search") {
                tooltip_text = _("Search")
            };
            headerbar.pack_end (search_button);
            search_button.clicked.connect (()=> {
                search_button.icon_name = headerstack.visible_child_name == "mode"? "com.github.gabutakut.gabutdm" : "system-search";
                headerstack.visible_child_name = headerstack.visible_child_name == "mode"? headerstack.visible_child_name = "search" : headerstack.visible_child_name = "mode";
                var row = (DownloadRow) list_box.get_selected_row ();
                if (row != null) {
                    list_box.unselect_row (row);
                }
            });
            headerstack.notify["visible-child"].connect (()=> {
                view_status ();
                search_entry.text = "";
            });
            var host_button = new Gtk.Button.from_icon_name ("go-home") {
                tooltip_text = _("Host")
            };
            headerbar.pack_end (host_button);
            host_button.clicked.connect (()=> {
                if (qrcode == null) {
                    qrcode = new QrCode (application);
                    qrcode.set_transient_for (this);
                    qrcode.show ();
                    qrcode.get_host.connect ((reboot)=> {
                        return get_host (reboot);
                    });
                    qrcode.close.connect (()=> {
                        qrcode = null;
                    });
                }
            });
            var property_button = new Gtk.Button.from_icon_name ("document-properties") {
                tooltip_text = _("Property")
            };
            properties = new GLib.List<AddUrl> ();
            property_button.clicked.connect (()=> {
                var row = (DownloadRow) list_box.get_selected_row ();
                if (row != null) {
                    if (!property_active (row)) {
                        var property = new AddUrl.Property (application);
                        property.show ();
                        properties.append (property);
                        property.property (row);
                        property.save_button.clicked.connect (()=> {
                            row = property.row;
                        });
                        property.close.connect (()=> {
                            properties.foreach ((proper)=> {
                                if (proper == property) {
                                    properties.remove_link (properties.find (proper));
                                }
                            });
                        });
                    }
                }
            });
            property_rev = new Gtk.Revealer () {
                transition_type = Gtk.RevealerTransitionType.CROSSFADE
            };
            property_rev.set_child (property_button);
            headerbar.pack_end (property_rev);
            list_box.row_selected.connect ((row)=> {
                property_rev.reveal_child = row != null? true : false;
            });
            var add_button = new Gtk.Button.from_icon_name ("insert-link") {
                tooltip_text = _("add link")
            };
            add_button.clicked.connect (()=> {
                send_file ("");
            });
            headerbar.pack_start (add_button);
            var torrentbutton = new Gtk.Button.from_icon_name ("document-open") {
                tooltip_text = _("Open .torrent .metalink file")
            };
            headerbar.pack_start (torrentbutton);
            torrentbutton.clicked.connect (()=> {
                var files = run_open_file (this);
                foreach (var file in files) {
                    send_file (file.get_uri ());
                }
            });
            var resumeall_button = new Gtk.Button.from_icon_name ("media-playback-start") {
                tooltip_text = _("Start All")
            };
            headerbar.pack_start (resumeall_button);
            resumeall_button.clicked.connect (start_all);

            var stopall_button = new Gtk.Button.from_icon_name ("media-playback-pause") {
                tooltip_text = _("Pause All")
            };
            headerbar.pack_start (stopall_button);
            stopall_button.clicked.connect (stop_all);

            var removeall_button = new Gtk.Button.from_icon_name ("edit-delete") {
                tooltip_text = _("Remove All")
            };
            headerbar.pack_start (removeall_button);
            removeall_button.clicked.connect (remove_all);
            return headerbar;
        }

        private bool property_active (DownloadRow row) {
            bool active = false;
            properties.foreach ((propet)=> {
                if (propet.row == row) {
                    propet.present ();
                    active = true;
                }
            });
            return active;
        }

        public void save_all_download () {
            var downloads = new GLib.List<DownloadRow> ();
            int total = (int) listrow.length ();
            for (int i = 0; i < total; i++) {
                list_box.select_row (list_box.get_row_at_index (i));
                var row = (DownloadRow) list_box.get_selected_row ();
                if (row != null) {
                    if (((DownloadRow) row).url == "") {
                        return;
                    }
                    if (!db_option_exist (((DownloadRow) row).url)) {
                        set_dboptions (((DownloadRow) row).url, ((DownloadRow) row).hashoption);
                    } else {
                        update_optionts (((DownloadRow) row).url, ((DownloadRow) row).hashoption);
                    }
                    downloads.append ((DownloadRow) row);
                }
            }
            set_download (downloads);
        }

        public GLib.List<string> get_dl_row (int status) {
            var strlist = new GLib.List<string> ();
            int total = (int) listrow.length ();
            for (int i = 0; i < total; i++) {
                list_box.select_row (list_box.get_row_at_index (i));
                var row = (DownloadRow) list_box.get_selected_row ();
                if (row != null) {
                    if (((DownloadRow) row).status == status) {
                        strlist.append (((DownloadRow) row).ariagid);
                    }
                }
            }
            return strlist;
        }

        private Gtk.Box mode_headerbar () {
            var headerbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                hexpand = true,
                margin_top = 4,
                margin_bottom = 4,
                halign = Gtk.Align.CENTER,
                valign = Gtk.Align.CENTER
            };
            view_mode = new ModeButton () {
                hexpand = false
            };
            view_mode.append_text (_("All"));
            view_mode.append_text (_("Downloading"));
            view_mode.append_text (_("Paused"));
            view_mode.append_text (_("Complete"));
            view_mode.append_text (_("Waiting"));
            view_mode.append_text (_("Error"));
            view_mode.selected = 0;
            headerbar.append (view_mode);
            view_mode.notify["selected"].connect (view_status);
            return headerbar;
        }

        private Gtk.Box saarch_headerbar () {
            var headerbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 0) {
                hexpand = true,
                margin_top = 4,
                margin_bottom = 4,
                halign = Gtk.Align.CENTER,
                valign = Gtk.Align.CENTER
            };
            search_entry = new Gtk.SearchEntry () {
                placeholder_text = _("Find Here")
            };
            search_entry.search_changed.connect (view_status);
            headerbar.append (search_entry);
            return headerbar;
        }

        private void next_download () {
            int total = (int) listrow.length ();
            for (int i = 0; i < total; i++) {
                list_box.select_row (list_box.get_row_at_index (i));
                var row = (DownloadRow) list_box.get_selected_row ();
                if (row != null) {
                    list_box.unselect_row (row);
                    if (((DownloadRow) row).status == StatusMode.WAIT) {
                        aria_unpause (((DownloadRow) row).ariagid);
                        ((DownloadRow) row).idle_progress ();
                    }
                }
            }
        }

        public void fast_respond (string ariagid) {
            int total = (int) listrow.length ();
            for (int i = 0; i < total; i++) {
                list_box.select_row (list_box.get_row_at_index (i));
                var row = (DownloadRow) list_box.get_selected_row ();
                if (row != null) {
                    list_box.unselect_row (row);
                    if (((DownloadRow) row).ariagid == ariagid) {
                        ((DownloadRow) row).idle_progress ();
                    }
                }
            }
        }

        public void remove_all () {
            int total = (int) listrow.length ();
            for (int i = 0; i < total; i++) {
                list_box.select_row (list_box.get_row_at_index (0));
                var row = (DownloadRow) list_box.get_selected_row ();
                if (row != null) {
                    row.remove_down ();
                }
            }
            aria_purge_all ();
        }

        public void load_dowanload () {
            get_download ().foreach ((row)=> {
                if (!get_exist (row.url)) {
                    list_box.append (row);
                    listrow.append (row);
                    row.show ();
                    row.notify_property ("status");
                    row.notify["status"].connect (()=> {
                        switch (((DownloadRow) row).status) {
                            case StatusMode.PAUSED:
                            case StatusMode.COMPLETE:
                                next_download ();
                                remove_dbus.begin (((DownloadRow) row).rowbus);
                                break;
                            case StatusMode.ERROR:
                                next_download ();
                                remove_dbus.begin (((DownloadRow) row).rowbus);
                                break;
                            case StatusMode.WAIT:
                            case StatusMode.NOTHING:
                                remove_dbus.begin (((DownloadRow) row).rowbus);
                                break;
                            case StatusMode.ACTIVE:
                                if (!menudbus.get_exist (((DownloadRow) row).rowbus)) {
                                    append_dbus.begin (((DownloadRow) row).rowbus);
                                    view_status ();
                                }
                                return;
                        }
                        view_status ();
                    });
                    if (list_box.get_selected_row () == null) {
                        list_box.select_row (row);
                        list_box.row_activated (row);
                    }
                    row.delete_me.connect ((rw)=> {
                        list_box.remove (rw);
                        remove_dbus.begin (((DownloadRow) rw).rowbus);
                        next_download ();
                        view_status ();
                        listrow.remove_link (listrow.find (rw));
                    });
                }
            });
        }

        public void add_url_box (string url, Gee.HashMap<string, string> options, bool later, int linkmode) {
            if (get_exist (url)) {
                return;
            }
            var row = new DownloadRow.Url (url, options, linkmode);
            list_box.append (row);
            listrow.append (row);
            row.show ();
            row.notify["status"].connect (()=> {
                switch (((DownloadRow) row).status) {
                    case StatusMode.PAUSED:
                    case StatusMode.COMPLETE:
                        next_download ();
                        remove_dbus.begin (((DownloadRow) row).rowbus);
                        break;
                    case StatusMode.ERROR:
                        next_download ();
                        remove_dbus.begin (((DownloadRow) row).rowbus);
                        break;
                    case StatusMode.WAIT:
                    case StatusMode.NOTHING:
                        remove_dbus.begin (((DownloadRow) row).rowbus);
                        break;
                    case StatusMode.ACTIVE:
                        if (!menudbus.get_exist (((DownloadRow) row).rowbus)) {
                            append_dbus.begin (((DownloadRow) row).rowbus);
                            view_status ();
                        }
                        return;
                }
                view_status ();
            });
            row.delete_me.connect ((rw)=> {
                list_box.remove (rw);
                remove_dbus.begin (((DownloadRow) rw).rowbus);
                next_download ();
                view_status ();
                listrow.remove_link (listrow.find (rw));
            });
            if (list_box.get_selected_row () == null) {
                list_box.select_row (row);
                list_box.row_activated (row);
            }
            if (!later) {
                row.download ();
                row.start_notif ();
            } else {
                aria_pause (row.ariagid);
            }
        }

        private async void append_dbus (DbusmenuItem rowbus) throws GLib.Error {
            if (!menudbus.get_exist (rowbus)) {
                menudbus.child_append (rowbus);
            }
            yield open_quicklist (dbusserver, menudbus);
            set_badge.begin (globalactive);
        }

        private async void remove_dbus (DbusmenuItem rowbus) throws GLib.Error {
            if (menudbus.get_exist (rowbus)) {
                menudbus.child_delete (rowbus);
            }
            yield open_quicklist (dbusserver, menudbus);
            set_badge.begin (globalactive);
        }

        public override void show () {
            base.show ();
            remove_dbus.begin (openmenu);
        }

        private bool get_exist (string url) {
            bool linkexist = false;
            int total = (int) listrow.length ();
            for (int i = 0; i < total; i++) {
                list_box.select_row (list_box.get_row_at_index (i));
                var row = (DownloadRow) list_box.get_selected_row ();
                if (row != null) {
                    list_box.unselect_row (row);
                    if (((DownloadRow) row).url == url) {
                        linkexist = true;
                    }
                }
            }
            return linkexist;
        }

        private void start_all () {
            int total = (int) listrow.length ();
            for (int i = 0; i < total; i++) {
                list_box.select_row (list_box.get_row_at_index (i));
                var row = (DownloadRow) list_box.get_selected_row ();
                if (row != null) {
                    list_box.unselect_row (row);
                    if (((DownloadRow) row).status != StatusMode.COMPLETE && ((DownloadRow) row).status != StatusMode.ERROR) {
                        aria_unpause (((DownloadRow) row).ariagid);
                        ((DownloadRow) row).idle_progress ();
                    }
                }
            }
            view_status ();
        }

        private void stop_all () {
            aria_pause_all ();
            int total = (int) listrow.length ();
            for (int i = 0; i < total; i++) {
                list_box.select_row (list_box.get_row_at_index (i));
                var row = (DownloadRow) list_box.get_selected_row ();
                if (row != null) {
                    list_box.unselect_row (row);
                    if (((DownloadRow) row).status != StatusMode.COMPLETE && ((DownloadRow) row).status != StatusMode.ERROR) {
                        aria_pause (((DownloadRow) row).ariagid);
                        ((DownloadRow) row).update_progress ();
                    }
                }
            }
            view_status ();
        }

        public string set_selected (string ariagid, string selected) {
            string aria_gid = "";
            int total = (int) listrow.length ();
            for (int i = 0; i < total; i++) {
                list_box.select_row (list_box.get_row_at_index (i));
                var row = (DownloadRow) list_box.get_selected_row ();
                if (row != null) {
                    list_box.unselect_row (row);
                    if (((DownloadRow) row).ariagid == ariagid) {
                        aria_gid = ((DownloadRow) row).set_selected (selected);
                    }
                }
            }
            return aria_gid;
        }

        public bool has_visible_children () {
            int total = (int) listrow.length ();
            for (int i = 0; i < total; i++) {
                list_box.select_row (list_box.get_row_at_index (i));
                var row = (DownloadRow) list_box.get_selected_row ();
                if (row != null) {
                    list_box.unselect_row (row);
                    if (row.get_child_visible ()) {
                        return true;
                    }
                }
            }
            return false;
        }

        public void view_status () {
            if (headerstack.visible_child_name == "search") {
                if (search_entry.text.strip () == "") {
                    list_box.set_filter_func ((item) => {
                        return false;
                    });
                    var search_alert = new AlertView (
                        _("Find File"),
                        _("Mode Search Based on Filename."),
                        "system-search"
                    );
                    search_alert.show ();
                    list_box.set_placeholder (search_alert);
                    return;
                }
                list_box.set_filter_func ((item) => {
                    if (((DownloadRow) item).filename == null) {
                        return false;
                    }
                    return ((DownloadRow) item).filename.casefold ().contains (search_entry.text.casefold ());
                });
                if (!has_visible_children ()) {
                    var empty_alert = new AlertView (
                        _("No Search Found"),
                        _("insert Link, open file or Drag and Drop Torrent, Metalink, Magnet URIs."),
                        "system-search"
                    );
                    empty_alert.show ();
                    list_box.set_placeholder (empty_alert);
                } else {
                    list_box.set_placeholder (null);
                }
                return;
            }
            switch (view_mode.selected) {
                case 1:
                    list_box.set_filter_func ((item) => {
                        return ((DownloadRow) item).status == StatusMode.ACTIVE;
                    });
                    var active_alert = new AlertView (
                        _("No Active Download"),
                        _("insert Link, open file or Drag and Drop Torrent, Metalink, Magnet URIs."),
                        "com.github.gabutakut.gabutdm.active"
                    );
                    active_alert.show ();
                    list_box.set_placeholder (active_alert);
                    return;
                case 2:
                    list_box.set_filter_func ((item) => {
                        return ((DownloadRow) item).status == StatusMode.PAUSED;
                    });
                    var nopause_alert = new AlertView (
                        _("No Paused Download"),
                        _("insert Link, open file or Drag and Drop Torrent, Metalink, Magnet URIs."),
                        "com.github.gabutakut.gabutdm.pause"
                    );
                    nopause_alert.show ();
                    list_box.set_placeholder (nopause_alert);
                    return;
                case 3:
                    list_box.set_filter_func ((item) => {
                        return ((DownloadRow) item).status == StatusMode.COMPLETE;
                    });
                    var nocomp_alerst = new AlertView (
                        _("No Complete Download"),
                        _("insert Link, open file or Drag and Drop Torrent, Metalink, Magnet URIs."),
                        "com.github.gabutakut.gabutdm.complete"
                    );
                    nocomp_alerst.show ();
                    list_box.set_placeholder (nocomp_alerst);
                    return;
                case 4:
                    list_box.set_filter_func ((item) => {
                        return ((DownloadRow) item).status == StatusMode.WAIT;
                    });
                    var nowait_alert = new AlertView (
                        _("No Waiting Download"),
                        _("insert Link, open file or Drag and Drop Torrent, Metalink, Magnet URIs."),
                        "com.github.gabutakut.gabutdm.waiting"
                    );
                    nowait_alert.show ();
                    list_box.set_placeholder (nowait_alert);
                    return;
                case 5:
                    list_box.set_filter_func ((item) => {
                        return ((DownloadRow) item).status == StatusMode.ERROR;
                    });
                    var noerr_alert = new AlertView (
                        _("No Error Download"),
                        _("insert Link, open file or Drag and Drop Torrent, Metalink, Magnet URIs."),
                        "com.github.gabutakut.gabutdm.error"
                    );
                    noerr_alert.show ();
                    list_box.set_placeholder (noerr_alert);
                    return;
                default:
                    list_box.set_filter_func (null);
                    if (!has_visible_children ()) {
                        list_box.set_placeholder (nodown_alert);
                    }
                    return;
            }
        }
    }
}
