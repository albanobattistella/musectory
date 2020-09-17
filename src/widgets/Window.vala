/*
 * This file is part of tatam.
 * 
 *     tatam is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 * 
 *     tatam is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 * 
 *     You should have received a copy of the GNU General Public License
 *     along with tatam.  If not, see <http://www.gnu.org/licenses/>.
 * 
 * Copyright 2020 Takayuki Tanaka
 */

using Gtk;

namespace Tatam {
    public class Window : Gtk.Window {
        private const string[] icon_dirs = {
            "/usr/share/icons/hicolor/48x48/apps/",
            "/usr/local/share/icons/hicolor/48x48/apps/",
            "~/.icons"
        };

        private Tatam.HeaderBar header_bar;
        private Tatam.Stack stack;
        private Tatam.Sidebar sidebar;
        private Tatam.Finder finder;
        private Tatam.PlaylistBox playlist_view;
        private Tatam.Controller controller;

        private Revealer bookmark_revealer;
        private Button music_view_close_button;
        private TreeViewColumn bookmark_title_col;
        private Gdk.Screen screen;

        private Overlay music_view_overlay;
        private Image music_view_artwork;
        private ScrolledWindow music_view_container;
        private Label playlist_view_dir_label;
        private int saved_width;
        private int saved_height;

        private Tatam.GstPlayer music;
        
        private Dialog? help_dialog = null;
        private Dialog? save_playlist_dialog = null;
        
        private uint max_width;
        private uint max_height;
        private uint default_height;
        private uint default_width;
        
        private Tatam.Options options;
        private Tatam.FileInfoAdapter file_info_reader;
        
        public Window(Tatam.Options options) {
            this.options = options;

            screen = Gdk.Screen.get_default();
            debug("get screen: " + (screen != null ? "ok." : "failed"));

            max_width = screen.get_width();
            debug("Max width of the display: " + max_width.to_string());

            max_height = screen.get_height();
            debug("Max height of the display: " + max_height.to_string());

            default_height = (int) (max_height * 0.7);
            default_width = int.min((int) (max_width * 0.5), (int) (window_default_height * 1.3));

            artwork_max_size = int.min((int) max_width, (int) max_height);
            
            IconTheme icon_theme = Gtk.IconTheme.get_default();

            file_info_reader = new Tatam.FileInfoAdapter();

            try {
                file_pixbuf = icon_theme.load_icon(IconName.AUDIO_FILE, 64, 0);
                cd_pixbuf = icon_theme.load_icon(IconName.MEDIA_OPTICAL, 64, 0);
                folder_pixbuf = icon_theme.load_icon(IconName.FOLDER_MUSIC, 64, 0);
                if (folder_pixbuf == null) {
                    folder_pixbuf = icon_theme.load_icon(IconName.FOLDER, 64, 0);
                }
            } catch (Error e) {
                stderr.printf(Text.ERROR_LOAD_ICON);
                Process.exit(1);
            }

            construct_widgets();
        }

        private void construct_widgets() {
            header_bar = new Tatam.HeaderBar();
            {
                header_bar.switch_button_clicked.connect((switch_button_state) => {
                        if (switch_button_state == Tatam.HeaderBar.SwitchButtonState.PLAYLIST) {
                            Tatam.FileInfo file_info = playlist_view.track_data();
                            if (file_info.title != null) {
                                header_bar.set_title(file_info.title);
                            } else {
                                header_bar.set_title(file_info.name);
                            }
                            if (current_playing_artwork != null) {
                                controller.show_artwork();
                            }
                            music_view_artwork.visible = false;
                            stack.show_playlist();
                        } else {
                            header_bar.set_title(finder.dir_path);
                            if (current_playing_artwork != null) {
                                controller.show_artwork();
                            }
                            music_view_artwork.visible = false;
                            stack.show_finder();
                        }
                    });

                header_bar.add_button_clicked.connect(() => {
                        playlist_save_action();
                    });

                header_bar.fold_button_clicked.connect((fold_button_state) => {
                        if (fold_button_state == Tatam.HeaderBar.FoldButtonState.FOLDED) {
                            this.resize(this.get_allocated_width(), saved_this_height);
                            stack.show_stack();
                            controller.show_buttons();
                        } else {
                            saved_this_width = this.get_allocated_width();
                            saved_this_height = this.get_allocated_height();
                            this.resize(saved_this_width, 1);
                            stack.hide_stack();
                            controller.hide_buttons();
                        }
                    });

                header_bar.about_button_clicked.connect(() => {
                        show_about_dialog(this);
                    });
            }
            
            var top_box = new Box(Orientation.VERTICAL, 0);
            {
                var main_overlay = new Overlay();
                {
                    stack = new Tatam.Stack();
                    {
                        var finder_paned = new Paned(Orientation.HORIZONTAL);
                        {
                            sidebar = new Tatam.Sidebar();
                            {
                                sidebar.bookmark_directory_selected.connect((dir_path) => {
                                        finder.change_dir.begin((string) dir_path);
                                        finder_add_button.sensitive = true;
                                        current_dir = (string) dir_path;
                                        header_bar.set_title(PROGRAM_NAME + ": " + current_dir);
                                    });

                                sidebar.bookmark_del_button_clicked.connect(() => {
                                        if (dirs.length() > 1) {
                                            if (Dialogs.confirm(Text.CONFIRM_REMOVE_BOOKMARK, this)) {
                                                dirs.remove_link(dirs.nth(path.get_indices()[1]));
                                                return true;
                                            }
                                        }
                                        return false;
                                    });

                                sidebar.playlist_selected.connect((playlist_name, playlist_path) => {
                                        if (music.playing) {
                                            music.quit();
                                        }
                                        Idle.add(() => {
                                                if (music.playing) {
                                                    return Source.CONTINUE;
                                                } else {
                                                    load_playlist_from_file(playlist_name, playlist_path);
                                                    return Source.REMOVE;
                                                }
                                            });
                                    });

                                sidebar.playlist_del_button_clicked.connect((playlist_path) => {
                                        if (Dialogs.confirm(Text.CONFIRM_REMOVE_PLAYLIST, this)) {
                                            FileUtils.remove(playlist_path);
                                            return true;
                                        }
                                        return false;
                                    });
            
                                sidebar.file_chooser_called.connect(() => {
                                        string dir_name = Dialogs.choose_directory(this);
                                        current_dir = dir_name;
                                        debug("selected file path: %s", current_dir);
                                        finder.change_dir.begin(current_dir);
                                        header_bar.set_title(current_dir);
                                        finder_add_button.sensitive = true;
                                    });

                                sidebar.bookmark_added.connect((file_path) => {
                                        dirs.add(file_path);
                                    });
                            }
                            
                            var finder_box = new Box(Orientation.VERTICAL, 4);
                            {
                                finder_toolbar = new FinderToolbar();
                                {
                                    finder_toolbar.parent_button_clicked.connect(() => {
                                            string path = File.new_for_path(current_dir).get_parent().get_path();
                                            finder.change_dir.begin(path);
                                            finder.file_button_clicked(path);
                                        });

                                    finder_toolbar.zoomin_button_clicked.connect(() => {
                                            finder.zoom_in();
                                        });

                                    finder_toolbar.zoomout_button_clicked.connect(() => {
                                            finder.zoom_out();
                                        });

                                    finder_toolbar.location_entered.connect((location) => {
                                            if (GLib.FileUtils.test(text, FileTest.IS_DIR)) {
                                                finder.change_dir.begin(text);
                                            }
                                        });

                                    finder_toolbar.refresh_button_clicked.connect(() => {
                                            finder.change_dir.begin(current_dir);
                                        });

                                    finder_toolbar.add_button_clicked.connect(() => {
                                            playlist_save_action();
                                        });
                                }
                                
                                var finder_overlay = new Overlay();
                                {
                                    finder = new Tatam.Finder
                                    .Builder()
                                    .file_pixbuf(file_pixbuf)
                                    .disc_pixbuf(cd_pixbuf)
                                    .folder_pixbuf(folder_pixbuf)
                                    .parent_pixbuf(parent_pixbuf)
                                    .build();
                                    {
                                        finder.set_default_icon_size(options.icon_size);

                                        finder.dir_changed.connect((path) => {
                                                finder_location.buffer.set_text(path.data);
                                                finder_add_button.sensitive = true;
                                            });
                    
                                        finder.bookmark_button_clicked.connect((file_path) => {
                                                add_bookmark(file_path);
                                            });

                                        finder.play_button_clicked.connect((file_path) => {
                                                finder.change_cursor(Gdk.CursorType.WATCH);
                    
                                                if (music.playing) {
                                                    music.quit();
                                                }
                    
                                                Idle.add(() => {
                                                        if (music.playing) {
                                                            return Source.CONTINUE;
                                                        } else {
                                                            debug("file_path: %s", file_path);
                                                            playlist_view.new_list_from_path(file_path);
                                                            var file_path_list = playlist_view.get_file_path_list();
                                                            if (GLib.FileUtils.test(file_path, FileTest.IS_REGULAR)) {
                                                                music.start(ref file_path_list, options.ao_type);
                                                                int index = playlist_view.get_index_from_path(file_path);
                                                                if (index > 0) {
                                                                    music.play_next(index);
                                                                }
                                                            } else {
                                                                music.start(ref file_path_list, options.ao_type);
                                                            }
                                                            ((Gtk.Image)play_pause_button.icon_widget).icon_name = IconName.Symbolic.MEDIA_PLAYBACK_PAUSE;
                                                            header_bar.switch_button_icon_name = IconName.Symbolic.GO_PREVIOUS;
                                                            header_bar.enable_switch_button();
                                                            stack.show_playlist();
                                                            finder.change_cursor(Gdk.CursorType.LEFT_PTR);
                                                            return Source.REMOVE;
                                                        }
                                                    });
                                            });

                                        finder.add_button_clicked.connect((file_path) => {
                                                playlist_view.append_list_from_path(file_path);
                                                Gee.List<string> file_list = playlist_view.get_file_path_list();
                                                playlist_view.changed(file_list);
                                            });

                                        finder.icon_image_resized.connect((icon_size) => {
                                                options.icon_size = icon_size;
                                            });

                                        finder.file_button_clicked.connect((file_path) => {
                                                if (GLib.FileUtils.test(file_path, FileTest.IS_DIR)) {
                                                    current_dir = file_path;
                                                    header_bar.set_title(current_dir);
                                                }
                                            });

                                        finder.use_popover = false;
                                    }
                                    
                                    finder_overlay.add(finder);
                                }

                                finder_box.pack_start(finder_toolbar, false, false);
                                finder_box.pack_start(finder_overlay, true, true);
                            }
        
                            finder_paned.pack1(sidebar, false, true);
                            finder_paned.pack2(finder_box, true, true);
                        }
                        
                        var playlist_vbox = new Box(Orientation.HORIZONTAL, 0);
                        {
                            var playlist_view_container = new ScrolledWindow(null, null);
                            {
                                playlist_view = new PlaylistBox();
                                {
                                    playlist_view.image_size = options.playlist_image_size;
                                    playlist_view.list_box.row_activated.connect((row) => {
                                            int index = row.get_index();
                                            debug("playlist view was clicked (row_activated at %u).", index);
                                            int step = ((int) index) - ((int) playlist_view.get_track());
                        
                                            if (step == 0) {
                                                musi.cpause();
                                                playlist_view.toggle_status();
                                                var icon = ((Gtk.Image)play_pause_button.icon_widget);
                                                if (music.paused) {
                                                    controller.play_pause_button_state = Tatam.Controller.PlayPauseButtonState.PLAY;
                                                } else {
                                                    controller.play_pause_button_state = Tatam.Controller.PlayPauseButtonState.PAUSE;
                                                }
                                            } else {
                                                debug("playlist restarted from track %d", index);
                                                if (step > 0) {
                                                    music.play_next(step);
                                                } else if (step < 0) {
                                                    music.play_prev(-step);
                                                }
                                                music.paused = false;
                                            }

                                            return;
                                        });
                
                                    playlist_view.changed.connect((file_path_list) => {
                                            Gee.List<string> list = file_path_list.copy_deep((src) => {
                                                    return src.dup();
                                                });
                                            if (list.length() > 0) {
                                                finder_add_button.sensitive = true;
                                            }
                                            if (music.playing) {
                                                music.set_file_list(ref list);
                                            } else {
                                                music.start(ref list, options.ao_type);
                                                controller.play_pause_button_state = Tatam.Controller.PlayPauseButtonState.PAUSE;
                                                header_bar.switch_button_icon_name = IconName.Symbolic.VIEW_GRID;
                                                header_bar.enable_switch_button();
                                                stack.show_playlist();
                                            }
                                            next_track_button.sensitive = true;
                                        });
                                }
                                playlist_view_container.add(playlist);
                            }

                            playlist_vbox.pack_start(playlist_view_container, true, true);
                        }
                        
                        stack.add_named(finder_paned, "finder");
                        stack.add_named(playlist_vbox, "playlist");
                        stack.finder_is_selected.connect(() => {
                                header_bar.show_add_button();
                            });
                        stack.playlist_is_selected.connect(() => {
                                header_bar.show_add_button();
                            });
                    }
                
                    music_view_overlay = new Overlay();
                    {
                        music_view_close_button = new Button.from_icon_name(
                            IconName.Symbolic.WINDOW_CLOSE, IconSize.BUTTON);
                        {
                            music_view_close_button.halign = Align.END;
                            music_view_close_button.valign = Align.START;
                            music_view_close_button.margin = 10;
                            music_view_close_button.clicked.connect(() => {
                                    controller.show_artwork();
                                    music_view_overlay.visible = false;
                                    header_bar.enable_switch_button();
                                    finder_add_button.sensitive = true;
                                });
                        }

                        music_view_container = new ScrolledWindow(null, null);
                        {
                            music_view_container.get_style_context().add_class(
                                StyleClass.ARTWORK_BACKGROUND);
                        }

                        music_view_artwork = new Image();
                        {
                            music_view_artwork.margin = 0;
                            music_view_container.add(music_view_artwork);
                        }

                        music_view_overlay.add(music_view_container);
                        music_view_overlay.add_overlay(music_view_close_button);
                        music_view_overlay.set_overlay_pass_through(music_view_close_button, true);
                    }
                    
                    main_overlay.add(stack);
                    main_overlay.add_overlay(music_view_overlay);
                }

                controller = new Tatam.Controller();
                {
                    controller.play_button_clicked.connect(() => {
                            debug("controller.play_button_clicked");
                            if (!music.playing) {
                                music.play(playlist_view.get_item().path);
                            } else {
                                music.unpause();
                            }

                            //-----------------------------------------

                            finder.change_cursor(Gdk.CursorType.WATCH);
                            Idle.add(() => {
                                    debug("play-pause button was clicked. music is not playing. start it.");
                                    if (stack.finder_is_visible()) {
                                        playlist_view.new_list_from_path(finder.dir_path);
                                    }
                                    stack.show_playlist();
                                    header_bar.enable_switch_button();
                                    header_bar.switch_button_icon_name = IconName.GO_PREVIOUS;
                                    var file_path_list = playlist_view.get_file_path_list();
                                    music.start(ref file_path_list, options.ao_type);
                                    finder.change_cursor(Gdk.CursorType.LEFT_PTR);
                                    return Source.REMOVE;
                                });
                        });

                    controller.pause_button_clicked.connect(() => {
                            debug("controller.pause_button_clicked");
                            music.pause();

                            //-----------------------------------------

                            debug("play-pause button was clicked. music is playing. pause it.");
                            music.pause();
                            playlist_view.toggle_status();
                            var icon = ((Gtk.Image)play_pause_button.icon_widget);
                            if (music.paused) {
                                icon.icon_name = IconName.Symbolic.MEDIA_PLAYBACK_START;
                            } else {
                                icon.icon_name = IconName.Symbolic.MEDIA_PLAYBACK_PAUSE;
                            }
                        });

                    controller.next_button_clicked.connect(() => {
                            debug("controller.next_button_clicked");
                            if (!playlist_view.track_is_last()) {
                                playlist_view.move_to_next_track();
                                set_controller_artwork();
                                music.play(playlist_view.get_item().path);
                            }
                        });

                    controller.prev_button_clicked.connect(() => {
                            debug("controller.prev_button_clicked");
                            if (music.playing) {
                                if (controller.music_current_time > 1000) {
                                    controller.music_current_time = 0;
                                    music.quit();
                                    music.play(playlist_view.get_item().path);
                                } else if (!playlist_view.track_is_first()) {
                                    playlist_view.move_to_prev_track();
                                    set_controller_artwork();
                                    music.play(playlist_view.get_item().path);
                                }
                            }
                        });

                    controller.time_position_changed.connect((new_value) => {
                            debug("controller.time_position_changed");
                            music.set_position(new Tatam.SmallTime.from_milliseconds((uint) new_value));
                        });

                    controller.volume_changed.connect((value) => {
                            debug("controller.volume_changed");
                            music.volume = value;
                        });

                    controller.artwork_clicked.connect(() => {
                            header_bar.set_title(music_title.label);
                            music_view_overlay.visible = true;

                            Timeout.add(300, () => {
                                    debug("enter timeout artwork_button.clicked");
                                    int size = int.min(music_view_container.get_allocated_width(),
                                                       music_view_container.get_allocated_height());
                                    music_view_artwork.pixbuf = MyUtils.PixbufUtils.scale(current_playing_artwork, size);
                                    music_view_artwork.visible = true;
                                    header_bar.disable_switch_button();
                                    return Source.REMOVE;
                                });
                        });

                    controller.time_position_changed.connect((value) => {
                            music_time_position = music_total_time_seconds * value;
                            music.move_pos((int) (value * 100));
                        });

                    controller.shuffle_button_toggled((shuffle_on) => {
                            playlist_view.toggle_shuffle();
                            music.toggle_shuffle();
                        });                

                    controller.repeat_button_toggled((repeat_on) => {
                            playlist_view.toggle_repeat();
                            music.toggle_repeat();
                        });
                }
                
                top_box.pack_start(main_overlay, true, true);
                top_box.pack_start(controller, false, false);
            }

            this.add(top_box);
            this.set_titlebar(header_bar);
            this.border_width = 0;
            this.window_position = WindowPosition.CENTER;
            this.resizable = true;
            this.has_resize_grip = true;
            this.set_default_size(window_default_width, window_default_height);

            this.destroy.connect(application_quit);
            this.configure_event.connect((cr) => {
                    if (music_view_overlay.visible && current_playing_artwork != null) {
                        int size = int.min(music_view_container.get_allocated_width(),
                                           music_view_container.get_allocated_height());
                        music_view_artwork.pixbuf = MyUtils.PixbufUtils.scale(current_playing_artwork, size);
                    }
                    bookmark_title_col.max_width = this.get_allocated_width() / 4;
                    return false;
                });

            this.show_all();

            if (GLib.FileUtils.test(css_path, FileTest.EXISTS)) {
                Gdk.Screen win_screen = this.get_screen();
                CssProvider css_provider = new CssProvider();
                try {
                    css_provider.load_from_path(css_path);
                } catch (Error e) {
                    debug("ERROR: css_path: %s", css_path);
                    stderr.printf(Text.ERROR_CREATE_WINDOW);
                    return 1;
                }
                Gtk.StyleContext.add_provider_for_screen(win_screen,
                                                         css_provider,
                                                         Gtk.STYLE_PROVIDER_PRIORITY_USER);
            }

            controller.hide_artwork();
            controller.deactivate_buttons();

            music_view_overlay.visible = false;
            music_view_artwork.visible = false;
            finder.hide_while_label();
            Image header_switch_button_icon = header_switch_button.image as Image;
            if (header_switch_button_icon != null) {
                header_switch_button_icon.icon_name = IconName.Symbolic.VIEW_LIST;
            }
            header_switch_button.sensitive = false;
            finder_toolbar.activate_buttons();
            stack.show_finder();
            finder.change_dir.begin(current_dir);
            if (options.last_playlist_name != "") {
                load_playlist_from_file(options.last_playlist_name,
                                        get_playlist_path_from_name(options.last_playlist_name));
            }
        }

        private void setup_music() {
            music = new Tatam.GstPlayer();
            music.volume = 0.5;

            music.started.connect(() => {
                    debug("music.started was called");
                    set_controller_artwork();
                    controller.play_pause_button_state = Tatam.Controller.PlayPauseButtonState.PLAY;
                    
                    header_bar.set_title(music_title.label);
                    playlist_view.set_track(track_number);

                });

            music.error_occured.connect((error) => {
                    debug("music.error_occured was called");
                    stderr.printf(@"Error: $(error.message)\n");
                });

            music.finished.connect(() => {
                    debug("music.finished was called");
                    if (!playlist_view.track_is_last()) {
                        debug("playlist has next track");
                        playlist_view.move_to_next_track();
                        music.play(playlist_view.get_item().path);
                    } else {
                        debug("playing all files is completed!");
                    }
                });

            music.unpaused.connect(() => {
                    print("music.unpaused was called\n");
                });

            music.paused.connect(() => {
                    print("music.paused was called\n");
                });
        }
        
        private void set_controller_artwork() {
            Tatam.FileInfo? info = playlist_view.get_item();
            if (info == null) {
                return;
            }
            if (info.title != null) {
                controller.music_title = info.title;
            } else {
                controller.music_title = info.name;
            }
            controller.music_total_time = info.time_length.milliseconds;
            controller.activate_buttons(playlist_view.track_is_first(), playlist_view.track_is_last());
            if (info.artwork != null) {
                controller.set_artwork(info.artwork);
            }
            print_file_info_pretty(info);
            debug("set_controller_artwork is completed");
        }

        private void playlist_save_action() {
            if (stack.finder_is_visible()) {
                add_bookmark(finder.dir_path);
            } else if (stack.playlist_is_visible()) {
                if (playlist_view.name == null) {
                    save_playlist(playlist_view.get_file_path_list());
                } else if (playlist_exists(playlist_view.name)) {
                    if (Dialogs.confirm(Text.CONFIRM_OVERWRITE.printf(playlist_view.name), this)) {
                        overwrite_playlist_file(playlist_view.name, playlist_view.get_file_path_list());
                    } else {
                        save_playlist(playlist_view.get_file_path_list());
                    }
                }
            }
        }

        private void application_quit() {
            if (music.playing) {
                music.quit();
            }

            Idle.add(() => {
                    if (!music.playing) {
                        Gtk.main_quit();
                        if (playlist_view.name != null) {
                            options.last_playlist_name = playlist_view.name;
                        }
                        return Source.REMOVE;
                    } else {
                        return Source.CONTINUE;
                    }
                });
        }

        private void show_about_dialog() {
            if (help_dialog == null) {
                help_dialog = new Dialog.with_buttons(PROGRAM_NAME + " info",
                                                      this,
                                                      DialogFlags.MODAL | DialogFlags.DESTROY_WITH_PARENT,
                                                      "_OK",
                                                      ResponseType.NONE);
                {
                    var help_dialog_vbox = new Box(Orientation.VERTICAL, 0);
                    {
                        var help_dialog_label_text = new Label("<span size=\"24000\"><b>" + PROGRAM_NAME + "</b></span>");
                        help_dialog_label_text.use_markup = true;
                        help_dialog_label_text.margin = 10;

                        help_dialog_vbox.pack_start(new Image.from_pixbuf(get_application_icon_at_size(64, 64)));
                        help_dialog_vbox.pack_start(help_dialog_label_text, false, false);
                        help_dialog_vbox.pack_start(new Label(Text.DESCRIPTION), false, false);
                        help_dialog_vbox.pack_start(new Label(Text.COPYRIGHT), false, false);
                        help_dialog_vbox.margin = 20;
                    }
                    help_dialog.get_content_area().add(help_dialog_vbox);
                    help_dialog.response.connect(() => {
                            help_dialog.visible = false;
                        });
                    help_dialog.destroy.connect(() => {
                            help_dialog = null;
                        });
                    help_dialog.show_all();
                }
            }
            help_dialog.visible = true;
        }

        void save_playlist(Gee.List<string> file_path_list) {
            if (save_playlist_dialog == null) {
                Entry playlist_name_entry;

                Gee.List<string> copy_of_list = file_path_list.copy_deep((src) => {
                        return ((string)src).dup();
                    });

                save_playlist_dialog = new Dialog.with_buttons(PROGRAM_NAME + ": save playlist",
                                                               this,
                                                               DialogFlags.MODAL | DialogFlags.DESTROY_WITH_PARENT,
                                                               Text.DIALOG_OK,
                                                               ResponseType.ACCEPT,
                                                               Text.DIALOG_CANCEL,
                                                               ResponseType.CANCEL);
                {
                    var save_playlist_dialog_hbox = new Box(Orientation.HORIZONTAL, 5);
                    {
                        var label = new Label(Text.PLAYLIST_SAVE_NAME);
                        playlist_name_entry = new Entry();
                        save_playlist_dialog_hbox.pack_start(label);
                        save_playlist_dialog_hbox.pack_start(playlist_name_entry);
                    }
            
                    save_playlist_dialog.get_content_area().add(save_playlist_dialog_hbox);

                    save_playlist_dialog.response.connect((response_id) => {
                            if (response_id == ResponseType.ACCEPT) {
                                string playlist_name = playlist_name_entry.text;
                                string playlist_path = get_playlist_path_from_name(playlist_name);
                                sidebar.add_playlist(playlist_name, playlist_path);
                                debug("playlist name was saved: %s", playlist_name);
                                overwrite_playlist_file(playlist_name, copy_of_list);
                                playlist_view.name = playlist_name;
                            }
                            playlist_name_entry.text = Text.EMPTY;
                            save_playlist_dialog.visible = false;
                        });

                    save_playlist_dialog.destroy.connect(() => {
                            save_playlist_dialog = null;
                        });

                    save_playlist_dialog.show_all();
                }
            } else {
                save_playlist_dialog.visible = true;
            }
        }

        private void overwrite_playlist_file(string playlist_name, Gee.List<string> file_path_list) {
            string playlist_file_path = get_playlist_path_from_name(playlist_name);
            string playlist_file_contents = "";
            foreach (string file_path in file_path_list) {
                debug("overwrite_playlist_file: path=%s", file_path);
                playlist_file_contents += file_path + "\n";
            }
            debug("Begin new saved playlist contents:%s", playlist_file_path);
            debug(playlist_file_contents);
            debug("End new saved playlist contents");
            try {
                FileUtils.set_contents(playlist_file_path, playlist_file_contents);
                debug("playlist file has been saved");
            } catch (Error e) {
                stderr.printf(Text.ERROR_WRITE_CONFIG);
                Process.exit(1);
            }
        }

        private void load_playlist_from_file(string playlist_name, string playlist_path) {
            header_switch_button.sensitive = true;
            finder_add_button.sensitive = true;
            playlist_view.name = playlist_name;
            playlist_view.load_list_from_file(playlist_path);
            var file_path_list = playlist_view.get_file_path_list();
            music.start(ref file_path_list, options.ao_type);
            stack.show_playlist();
        }

        private Gdk.Pixbuf? get_application_icon_at_size(uint width, uint height) {
            try {
                foreach (string dir in icon_dirs) {
                    if (dir.index_of_char('~') == 0) {
                        dir = dir.replace("~", Environment.get_home_dir());
                    }
                    string icon_name = dir + "/" + PROGRAM_NAME + ".png";
                    debug("icon path : " + icon_name);
                    if (GLib.FileUtils.test(icon_name, FileTest.EXISTS)) {
                        return new Gdk.Pixbuf.from_file_at_size(icon_name, 64, 64);
                    }
                }
                return null;
            } catch (Error e) {
                return null;
            }
        }

        private string get_playlist_path_from_name(string name) {
            return Environment.get_home_dir() + "/." + PROGRAM_NAME + "/" + name + ".m3u";
        }
    }
}