/*
 * Diodon - GTK+ clipboard manager.
 * Copyright (C) 2010-2014 Diodon Team <diodon-team@lists.launchpad.net>
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
     * This class is in charge to grab keybindings on the X11 display
     * and filter X11-events and passing on such events to the registed
     * handler methods.
     */
    public class KeybindingManager : GLib.Object
    {
        private ShellKeyGrabber key_grabber;
        
        /**
         * list of binded keybindings
         */
        private Gee.List<Keybinding> bindings = new Gee.ArrayList<Keybinding>();
        
        /**
         * locked modifiers used to grab all keys whatever lock key
         * is pressed.
         */
        private static uint[] lock_modifiers = {
            0,
            Gdk.ModifierType.MOD2_MASK, // NUM_LOCK
            Gdk.ModifierType.LOCK_MASK, // CAPS_LOCK
            Gdk.ModifierType.MOD5_MASK, // SCROLL_LOCK
            Gdk.ModifierType.MOD2_MASK|Gdk.ModifierType.LOCK_MASK,
            Gdk.ModifierType.MOD2_MASK|Gdk.ModifierType.MOD5_MASK,
            Gdk.ModifierType.LOCK_MASK|Gdk.ModifierType.MOD5_MASK,
            Gdk.ModifierType.MOD2_MASK|Gdk.ModifierType.LOCK_MASK|Gdk.ModifierType.MOD5_MASK
        };
        
        /**
         * Helper class to store keybinding
         */
        private class Keybinding
        {
            public Keybinding(string accelerator, int keycode,
                Gdk.ModifierType modifiers, KeybindingHandlerFunc handler)
            {
                this.accelerator = accelerator;
                this.keycode = keycode;
                this.modifiers = modifiers;
                this.handler = handler;
            }
            
            public Keybinding.with_action(string accelerator, uint action, KeybindingHandlerFunc handler)
            {
                this.accelerator = accelerator;
                this.action = action;
                this.handler = handler;
            }
        
            public string accelerator { get; set; }
            public int keycode { get; set; }
            public Gdk.ModifierType modifiers { get; set; }
            public uint action { get; set; }
            public unowned KeybindingHandlerFunc handler { get; set; }
        }
        
        /**
         * Keybinding func needed to bind key to handler
         * 
         * @param event passing on gdk event
         */
        public delegate void KeybindingHandlerFunc();
    
        public KeybindingManager()
        {
            // init filter to retrieve X.Events
            /*Gdk.Window rootwin = Gdk.get_default_root_window();
            if(rootwin != null) {
                rootwin.add_filter(event_filter);
            }*/
            
            try {
                key_grabber = Bus.get_proxy_sync(BusType.SESSION, "org.gnome.Shell", "/org/gnome/Shell");
                key_grabber.accelerator_activated.connect(on_accelerator_activated);
            } catch(GLib.IOError e) {
                debug("org.gnome.Shell not avaialble. Cause: %s. Falling back to legacy mode", e.message);
                // TODO fall back to legacy mode
            }
        }
        
        ~KeybindingManager() {
            // keybindings always have to be unbinded otherwise there are lost
            // for the whole session
            unbind_all();
        }
        
        /**
         * Bind accelerator to given handler
         *
         * @param accelerator accelerator parsable by Gtk.accelerator_parse
         * @param handler handler called when given accelerator is pressed
         */
        public void bind(string accelerator, KeybindingHandlerFunc handler) throws IOError
        {
            debug("Binding key " + accelerator);
            
            uint action = key_grabber.grab_accelerator(accelerator, 0);
            debug("Key %s binded to action id %u", accelerator, action);
            Keybinding binding = new Keybinding.with_action(accelerator, action, handler);
            bindings.add(binding);
            
            // convert accelerator
            /*uint keysym;
            Gdk.ModifierType modifiers;
            Gtk.accelerator_parse(accelerator, out keysym, out modifiers);

            unowned X.Display display = Gdk.x11_get_default_xdisplay();
            int keycode = display.keysym_to_keycode(keysym);
                     
            if(keycode != 0) {
                X.Window root_window = Gdk.x11_get_default_root_xwindow();
                
                // trap XErrors to avoid closing of application
                // even when grabing of key fails
                Gdk.error_trap_push();

                // grab key finally
                // also grab all keys which are combined with a lock key such NumLock
                foreach(uint lock_modifier in lock_modifiers) {     
                    display.grab_key(keycode, modifiers|lock_modifier, root_window, false,
                        X.GrabMode.Async, X.GrabMode.Async);
                }
                
                // wait until all X request have been processed
                Gdk.flush();
                Gdk.error_trap_pop_ignored();
                
                // store binding
                Keybinding binding = new Keybinding(accelerator, keycode, modifiers, handler);
                bindings.add(binding);
                
                debug("Successfully binded key " + accelerator);
            }*/
        }
        
        /**
         * Unbind all registered accelerator
         */
        public void unbind_all() throws IOError
        {
            foreach(Keybinding binding in bindings) {
                debug("Unbinding key %s", binding.accelerator);
                key_grabber.ungrab_accelerator(binding.action);
            }
            
            bindings.clear();
        }
        
        /**
         * Unbind given accelerator.
         *
         * @param accelerator accelerator parsable by Gtk.accelerator_parse
         */
        public void unbind(string accelerator) throws IOError
        {
            debug("Unbinding key " + accelerator);
            
            /*unowned X.Display display = Gdk.x11_get_default_xdisplay();
            X.Window root_window = Gdk.x11_get_default_root_xwindow();
            
            // trap XErrors to avoid closing of application
            // even when grabing of key fails
            Gdk.error_trap_push();*/
            
            // unbind all keys with given accelerator
            Gee.List<Keybinding> remove_bindings = new Gee.ArrayList<Keybinding>();
            foreach(Keybinding binding in bindings) {
                if(str_equal(accelerator, binding.accelerator)) {
                    /*foreach(uint lock_modifier in lock_modifiers) {
                        display.ungrab_key(binding.keycode, binding.modifiers, root_window);
                    }*/
                    if(key_grabber.ungrab_accelerator(binding.action)) {
                        remove_bindings.add(binding);
                    }
                }
            }
            
            // wait until all X request have been processed
            /*Gdk.flush();
            Gdk.error_trap_pop_ignored();*/
            
            // remove unbinded keys
            bindings.remove_all(remove_bindings);
        }
        
        /**
         * Press given accelerator on current display on the window which
         * has focus at the time given.
         *
         * @param accelerator accelerator parsable by Gtk.accelerator_parse
         */
        public void press(string accelerator)
        {
            if(perform_key_event(accelerator, true, 100)) {
                debug("Successfully pressed key " + accelerator);
            }
        }
        
        /**
         * Release given accelerator on current display on the window which
         * has focus at the time given.
         *
         * @param accelerator accelerator parsable by Gtk.accelerator_parse
         */
        public void release(string accelerator)
        {
            if(perform_key_event(accelerator, false, 0)) {
                debug("Successfully released key " + accelerator);
            }
        }
        
        /**
         * Remove lock modifiers (NumLock, CapsLock, ScrollLock) from
         * key state
         *
         * @param state key state of a gdk event
         */
        public static uint remove_lockmodifiers(uint state)
        {
            return state & ~ (Gdk.ModifierType.MOD2_MASK|Gdk.ModifierType.LOCK_MASK|Gdk.ModifierType.MOD5_MASK);
        }
        
        /**
         * Helper method performing given accelerator on current active
         * window.
         *
         * @param accelerator accelerator parsable by Gtk.accelerator_parse
         * @param press true for press key; false for releasing
         * @param delay delay in milli seconds
         * @return true if creation was successful; otherwise false.
         */
        private bool perform_key_event(string accelerator, bool press, ulong delay)
        {
            // convert accelerator
            uint keysym;
            Gdk.ModifierType modifiers;
            Gtk.accelerator_parse(accelerator, out keysym, out modifiers);
            unowned X.Display display = Gdk.x11_get_default_xdisplay();
            int keycode = display.keysym_to_keycode(keysym);
            
            // FIXME: there must be an easier way
            int modifierykey = 0;
            switch(modifiers) {
                case Gdk.ModifierType.CONTROL_MASK:
                    // currently missing in the gdk binding
                    //modifierykey = Gdk.Key.Control_L;
                    modifierykey = 0xffe3;
                    break;
                case Gdk.ModifierType.SHIFT_MASK:
                    // currently missing in the gdk binding
                    //modifierykey = Gdk.Key.Shift_L;
                    modifierykey = 0xffe1;
                    break;
            }
            int modifiercode = display.keysym_to_keycode(modifierykey);
            
            if(keycode != 0) {
                
                if(modifiercode != 0) {
                    XTest.fake_key_event(display, modifiercode, press, delay);                
                }
                
                XTest.fake_key_event(display, keycode, press, delay);                
                
                return true;
            }
            
            return false;
        }
        
        /**
         * Triggered when ShellKeyGrabber detected pressed accelerator
         */
        private void on_accelerator_activated(uint action, uint device)
        {
            foreach(Keybinding binding in bindings) {
                if(binding.action == action) {
                    debug("Keybinding hit with action id %u and accelerator %s",
                        action, binding.accelerator);
                    binding.handler();
                }
            }
        }
        
        /**
         * Event filter method needed to fetch X.Events
         */
        private Gdk.FilterReturn event_filter(Gdk.XEvent gdk_xevent, Gdk.Event gdk_event)
        {
            X.Event* xevent = (X.Event*) gdk_xevent;
            
            // ungrab keyboard device so no more events are passed on
            // and interrupt following events till keyboard is grabbed again
            unowned Gdk.Display display = Gdk.Display.get_default();
            unowned Gdk.DeviceManager dm = display.get_device_manager();
            foreach(Gdk.Device device in dm.list_devices(Gdk.DeviceType.MASTER)) {
                if(device.get_source() == Gdk.InputSource.KEYBOARD) {
                    device.ungrab(Gtk.get_current_event_time());
                }
            }
            
            Gdk.flush();
            
            if(xevent->type == X.EventType.KeyPress) {
                debug("Key pressed, keycode: %u, modifiers: %u",
                    xevent->xkey.keycode, xevent->xkey.state);
                    
                foreach(Keybinding binding in bindings) {
                    uint event_mods = remove_lockmodifiers(xevent.xkey.state);
                    if(xevent->xkey.keycode == binding.keycode && event_mods == binding.modifiers) {
                        debug("Keybinding hit with accelerator %s",
                            binding.accelerator);
                        
                        // call all handlers with pressed key and modifiers
                        binding.handler();
                        return Gdk.FilterReturn.REMOVE;
                    }
                }
            }
             
            return Gdk.FilterReturn.CONTINUE;
        }
    }
}

