/*
 * Diodon - GTK+ clipboard manager.
 * Copyright (C) 2010-2013 Diodon Team <diodon-team@lists.launchpad.net>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published
 * by the Free Software Foundation, either version 2 of the License, or (at
 * your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
 * License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 * Author:
 *  Oliver Sauder <os@esite.ch>
 */

namespace Diodon
{
    /**
     * The controller is responsible to interact with all managers and views
     * passing on information between such and storing the application state
     * in the available models.
     */
    public class Controller : GLib.Object
    {
        private Settings settings_clipboard;
        private Settings settings_keybindings;
        private Settings settings_plugins;
        private Gee.Map<ClipboardType, ClipboardManager> clipboard_managers;
        private ZeitgeistClipboardStorage storage;
        private ClipboardConfiguration configuration;
        private PreferencesView preferences_view;
        private KeybindingManager keybinding_manager;
        private Peas.ExtensionSet extension_set;
        private Peas.Engine peas_engine;
        private ClipboardMenu recent_menu = null;
        private Gee.List<Gtk.MenuItem> static_recent_menu_items;
        
        /**
         * Called when a item has been selected.
         */
        public signal void on_select_item(IClipboardItem item);
        
        /**
         * Called when a new item is added
         */
        public signal void on_add_item(IClipboardItem item);
        
        /**
         * Called when a item needs to be removed
         */
        public signal void on_remove_item(IClipboardItem item);
        
        /**
         * Called when all items need to be cleared
         */
        public signal void on_clear();
        
        /**
         * Called after recent menu has been rebuilt
         */
        public signal void on_recent_menu_changed(Gtk.Menu recent_menu);
        
        public Controller()
        {            
            string diodon_dir = Utility.get_user_data_dir();
            clipboard_managers = new Gee.HashMap<ClipboardType, ClipboardManager>();
            
            keybinding_manager = new KeybindingManager();
            
            settings_clipboard = new Settings("net.launchpad.Diodon.clipboard");
            settings_keybindings = new Settings("net.launchpad.Diodon.keybindings");
            settings_plugins = new Settings("net.launchpad.Diodon.plugins");
            
            peas_engine = Peas.Engine.get_default();
            peas_engine.add_search_path(Config.PLUGINS_DIR, Config.PLUGINS_DATA_DIR);
            string user_plugins_dir = Path.build_filename(diodon_dir, "plugins");
            peas_engine.add_search_path(user_plugins_dir, user_plugins_dir);
            peas_engine.enable_loader("python");
            
            storage = new ZeitgeistClipboardStorage();
            
            configuration = new ClipboardConfiguration(); 
            
            clipboard_managers.set(ClipboardType.CLIPBOARD, new ClipboardManager(ClipboardType.CLIPBOARD, configuration));
            clipboard_managers.set(ClipboardType.PRIMARY, new PrimaryClipboardManager(configuration));  
            
            preferences_view = new PreferencesView();                  
        }
        
        private static void on_extension_added(Peas.ExtensionSet set, Peas.PluginInfo info, 
            Peas.Extension activatable)
        {
            ((Peas.Activatable)activatable).activate();
        }
        
        private static void on_extension_removed(Peas.ExtensionSet set, Peas.PluginInfo info, 
            Peas.Extension activatable)
        {   
            ((Peas.Activatable)activatable).deactivate();
        }
        
        /**
         * Initializes views, models and managers.
         */
        public async void init()
        {
            init_configuration();
            
            // make sure that recent menu gets rebuild when recent history changes
            yield rebuild_recent_menu();
            
            storage.on_items_deleted.connect(() => { rebuild_recent_menu.begin(); } );
            storage.on_items_inserted.connect(() => { rebuild_recent_menu.begin(); } );
            
            keybinding_manager.init();
            
            // init peas plugin system
            extension_set = new Peas.ExtensionSet(peas_engine, typeof(Peas.Activatable),
                "object", this);
            extension_set.@foreach((Peas.ExtensionSetForeachFunc)on_extension_added);
            
            extension_set.extension_added.connect((info, exten) => {
                ((Peas.Activatable)exten).activate();
            });
            extension_set.extension_removed.connect((info, exten) => {
                ((Peas.Activatable)exten).deactivate();
            });
            
            settings_plugins.bind("active-plugins", peas_engine, "loaded-plugins",
                SettingsBindFlags.DEFAULT);
        }
        
        /**
         * Initialize configuration values
         */
        private void init_configuration()
        {
            settings_clipboard.bind("synchronize-clipboards", configuration,
                "synchronize-clipboards", SettingsBindFlags.DEFAULT);

            settings_clipboard.bind("keep-clipboard-content", configuration,
                "keep-clipboard-content", SettingsBindFlags.DEFAULT);
            settings_clipboard.changed["keep-clipboard-content"].connect(
                (key) => {
                    enable_keep_clipboard_content(
                        configuration.keep_clipboard_content);
                }
            );
            enable_keep_clipboard_content(
                configuration.keep_clipboard_content);
            
            settings_clipboard.bind("instant-paste", configuration,
                "instant-paste", SettingsBindFlags.DEFAULT);
                
            settings_clipboard.bind("recent-items-size", configuration,
                "recent-items-size", SettingsBindFlags.DEFAULT);
            settings_clipboard.changed["recent-items-size"].connect(
                (key) => {
                    rebuild_recent_menu.begin();
                }
            );
            
            settings_keybindings.bind("history-accelerator", configuration,
                "history-accelerator", SettingsBindFlags.DEFAULT);
            settings_keybindings.changed["history-accelerator"].connect(
                (key) => {
                    change_history_accelerator(configuration.history_accelerator);
                }
            );
            change_history_accelerator(configuration.history_accelerator);
            
            // use clipboard and use primary needs to be initialized last as this
            // will start the polling of clipboard process
            settings_clipboard.bind("use-clipboard", configuration,
                "use-clipboard", SettingsBindFlags.DEFAULT);
            settings_clipboard.changed["use-clipboard"].connect(
                (key) => {
                    enable_clipboard_manager(ClipboardType.CLIPBOARD,
                        configuration.use_clipboard);
                }
            );
            enable_clipboard_manager(ClipboardType.CLIPBOARD,
                configuration.use_clipboard);
                
            settings_clipboard.bind("use-primary", configuration,
                "use-primary", SettingsBindFlags.DEFAULT);
            settings_clipboard.changed["use-primary"].connect(
                (key) => {
                    enable_clipboard_manager(ClipboardType.PRIMARY,
                        configuration.use_primary);
                }
            );
            enable_clipboard_manager(ClipboardType.PRIMARY,
                configuration.use_primary);
        }
        
        /**
         * Select a clipboard item identified by its checksum
         */
        public async void select_item_by_checksum(string checksum)
        {
            IClipboardItem item = yield storage.get_item_by_checksum(checksum);
            if(item != null) {
                yield select_item(item);
            }
        }
        
        /**
         * Select clipboard item. Discouraged to use as it usually means to hold
         * a complete item in memory before selecting it. See select_item_checksum
         * for an alternative.
         *
         * @param item item to be selected
         */
        public async void select_item(IClipboardItem item)
        {   
            yield storage.select_item(item, configuration.use_clipboard,
                configuration.use_primary);
            
            on_select_item(item);
            
            if(configuration.instant_paste) {
                execute_paste(item);
            }
        }

        /**
         * Execute paste instantly according to set preferences.
         * 
         * @param item item to be pasted
         */
        public void execute_paste(IClipboardItem item)
        {
            string key = null;
            if(configuration.use_clipboard) {
                key = "<Ctrl>V";
            }
            
            // prefer primary selection paste as such works
            // in more cases (e.g. terminal)
            // however it does not work with files and images
            if(configuration.use_primary && item is TextClipboardItem) {
                key = "<Shift>Insert";
            }
            
            if(key != null) {
                keybinding_manager.press(key);
                keybinding_manager.release(key);
            }
        }
        
        /**
         * Remove given item from view, storage and finally destroy
         * it gracefully.
         *
         * @param item item to be removed
         */
        public async void remove_item(IClipboardItem item)
        {
            yield storage.remove_item(item);
            on_remove_item(item);
        }
       
        /**
         * Add given text as text item to current clipboard history
         * 
         * @param text text to be added
         * @param origin origin of clipboard item as application path
         */
        public async void add_text_item(ClipboardType type, string text, string? origin)
        {
            IClipboardItem item = new TextClipboardItem(type, text, origin, new DateTime.now_utc());
            yield add_item(item);
        }
        
        /**
         * Handling paths retrieved from clipboard by adding it to the storage
         * and appending it to the menu of the indicator
         * 
         * @param paths paths received
         * @param origin origin of clipboard item as application path
         */
        public async void add_file_item(ClipboardType type, string paths, string? origin)
        {
            try {
                IClipboardItem item = new FileClipboardItem(type, paths, origin, new DateTime.now_utc());
                yield add_item(item);
            } catch(FileError e) {
                warning("Adding file(s) to history failed: " + e.message);
            }
        }
        
        /**
         * Handling image retrieved from clipboard bu adding it to the storage
         * and appending it to the menu of the indicator.
         *
         * @param origin origin of clipboard item as application path
         */
        public async void add_image_item(ClipboardType type, Gdk.Pixbuf pixbuf, string? origin)
        {
            try {
                IClipboardItem item = new ImageClipboardItem.with_image(type, pixbuf, origin, new DateTime.now_utc());
                yield add_item(item);
            } catch(GLib.Error e) {
                warning("Adding image to history failed: " + e.message);
            }
        }
        
        /**
         * Handling given item by checking if item is equal last added item
         * and if not so, adding it to history
         *
         * @param item item received
         */
        public async void add_item(IClipboardItem item)
        {
            ClipboardType type = item.get_clipboard_type();
            string label = item.get_label();
            IClipboardItem current_item = storage.get_current_item(type);
            
            // check if received item is different from last item
            if(current_item == null || !IClipboardItem.equal_func(current_item, item)) {
                debug("received item of type %s from clipboard %d with label %s",
                    item.get_type().name(), type, label);
                
                yield storage.add_item(item);
                on_add_item(item);

                if(configuration.synchronize_clipboards) {
                    synchronize(item);
                }
            }
        }
       
        /**
         * Get recent items whereas size is not bigger than configured recent
         * item size 
         * 
         * @param cats categories of recent items to get; null for all
         * @param date_copied filter results by given timerange; all per default
         * @param cancellable optional cancellable handler
         * @return list of recent clipboard items
         */ 
        public async Gee.List<IClipboardItem> get_recent_items(ClipboardCategory[]? cats = null,
            ClipboardTimerange date_copied = ClipboardTimerange.ALL, Cancellable? cancellable = null)
        {
            return yield storage.get_recent_items(configuration.recent_items_size, cats, date_copied, cancellable);
        }
        
        /**
         * Get clipboard items which match given search query
         *
         * @param search_query query to search items for
         * @param cats categories for search query or null for all
         * @param date_copied filter results by given timerange; all per default
         * @param cancellable optional cancellable handler
         * @return clipboard items matching given search query
         */
        public async Gee.List<IClipboardItem> get_items_by_search_query(string search_query,
            ClipboardCategory[]? cats = null, ClipboardTimerange date_copied = ClipboardTimerange.ALL,
            Cancellable? cancellable = null)
        {
            return yield storage.get_items_by_search_query(search_query, cats, date_copied, cancellable);
        }
        
        /**
         * Get currently selected item for given clipboard type
         * 
         * @param type clipboard type
         * @return clipboard item
         */
        public IClipboardItem get_current_item(ClipboardType type)
        {
            return storage.get_current_item(type);
        }
        
        /**
         * access to current configuration settings
         */
        public ClipboardConfiguration get_configuration()
        {
            return configuration;
        }
        
        /**
         * access to current keybinding manager
         */
        public KeybindingManager get_keybinding_manager()
        {
            return keybinding_manager;
        }
        
        /**
         * Set text on all other clipboards then current type
         */
        private void synchronize(IClipboardItem item)
        {
            // only text clipboard item can be synced
            if(item is TextClipboardItem) {
                ClipboardType type = item.get_clipboard_type();
                foreach(ClipboardManager clipboard_manager in clipboard_managers.values) {
                    if(type != clipboard_manager.clipboard_type) {
                        // check if item is already active in clipboard
                        // which will be synced to
                        IClipboardItem current_item = storage.get_current_item(
                            clipboard_manager.clipboard_type);
                        if(current_item == null || !IClipboardItem.equal_func(current_item, item)) {
                            clipboard_manager.select_item(item);
                        }
                    }
                }
            }
        }
        
        /**
         * Called when clipboard is empty and data might be needed to restored
         * 
         * @param type clipboard type
         */
        private void clipboard_empty(ClipboardType type)
        {               
            // check if a item is there to restore lost content
            IClipboardItem item = storage.get_current_item(type);
            if(item != null) {
                debug("Clipboard " + "%d".printf(type) + " is empty.");   
                ClipboardManager manager = clipboard_managers.get(type);
                manager.select_item(item);
            }
        }
        
        /**
         * change history accelerator key and bind new key to open_history.
         *
         * @param accelerator accelerator parseable by Gtk.accelerator_parse
         */        
        private void change_history_accelerator(string accelerator)
        {
            try {
                // check if there is a previos accelerator to unbind
                if(configuration.previous_history_accelerator != null) {
                    keybinding_manager.unbind(configuration.previous_history_accelerator);
                }
                
                // let's bind new one
                keybinding_manager.bind(accelerator, show_history);
            } catch(IOError e) {
                warning("Changing of history accelerator failed. Cause: %s", e.message);
            }
        }
        
        /**
         * Create clipboard menu with current recent items.
         */
        public async void rebuild_recent_menu()
        {
            Gee.List<IClipboardItem> items = yield get_recent_items();
            
            if(recent_menu != null) {
                recent_menu.destroy_menu();
            }
            
            recent_menu = new ClipboardMenu(this, items, static_recent_menu_items);
            on_recent_menu_changed(recent_menu);
        }
        
        /**
         * Add a static recent menu item which will always be shown below separator
         * even after recent menu has been rebuilt.
         *
         * @param menu_item menu item to be added
         */
        public async void add_static_recent_menu_item(Gtk.MenuItem menu_item)
        {
            if(static_recent_menu_items == null) {
                static_recent_menu_items = new Gee.ArrayList<Gtk.MenuItem>();
            }
            
            static_recent_menu_items.add(menu_item);
            yield rebuild_recent_menu();
        }
        
        /**
         * Remove static recent menu item so it won't appear on the recent menu 
         * anymore. This method doesn't dispose the menu item - caller
         * needs to take care of this in case menu item should be destroyed.
         *
         * @param menu_item item to be removed
         */
        public async void remove_static_recent_menu_item(Gtk.MenuItem menu_item)
        {
            if(static_recent_menu_items == null) {
                warning("Remove recent menu item has been called but no registered static recent menu items are available");
                return;
            }
            
            static_recent_menu_items.remove(menu_item);
            yield rebuild_recent_menu();
        }

        /**
         * Open menu to view history
         */        
        public void show_history()
        {
            recent_menu.show_menu();
        }
        
        /**
         * Get current recent menu. Recent menu can change at any time so
         * consider registering to on_recent_menu_changed() event. 
         */
        public Gtk.Menu get_recent_menu()
        {
            return recent_menu;
        }

        /**
         * connect/disconnect and attach/disattach to signals of given clipboard
         * type to enable/disable it.
         *
         * @param type type of clipboard
         * @param enable true for enabling; false for disabling
         */
        private void enable_clipboard_manager(ClipboardType type, bool enable)
        {
            ClipboardManager manager = clipboard_managers.get(type);
            
            if(enable) {
                manager.on_text_received.connect(add_text_item);
                manager.on_uris_received.connect(add_file_item);
                manager.on_image_received.connect(add_image_item);
                on_select_item.connect(manager.select_item);
                on_clear.connect(manager.clear);
                manager.start();
            }
            else {
                manager.stop();
                manager.on_text_received.disconnect(add_text_item);
                manager.on_uris_received.disconnect(add_file_item);
                manager.on_image_received.disconnect(add_image_item);
                on_select_item.disconnect(manager.select_item);
                on_clear.disconnect(manager.clear);    
            }
        }
                
        /**
         * connect/disconnect to signals of all clipboard manager to
         * enable/disable keep clipboard content support
         * 
         * @param enable true for enabling; false for disabling
         */
        private void enable_keep_clipboard_content(bool enable)
        {
            foreach(ClipboardManager clipboard_manager in clipboard_managers.values) {
                if(enable) {
                    clipboard_manager.on_empty.connect(clipboard_empty);
                }
                else {
                    clipboard_manager.on_empty.disconnect(clipboard_empty);    
                }
            }
        }
        
        /**
         * Show preferences dialog
         */
        public void show_preferences()
        {
            preferences_view.show(configuration);
        }
        
        /**
         * Clear all clipboard items from history
         */
        public async void clear()
        {
            yield storage.clear();
            on_clear();
        }
        
        /**
         * Quit diodon
         */
        public void quit()
        {
            Gtk.main_quit();
        }
        
        public override void dispose()
        {
            // shutdown all plugins
            extension_set.@foreach((Peas.ExtensionSetForeachFunc)on_extension_removed);
            keybinding_manager.dispose();
            
            base.dispose();
        }
    }  
}

