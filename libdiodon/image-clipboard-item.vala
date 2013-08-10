/*
 * Diodon - GTK+ clipboard manager.
 * Copyright (C) 2011-2013 Diodon Team <diodon-team@lists.launchpad.net>
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
     * Represents a image clipboard item holding. For memory consumption
     * reasons the pixbuf is not hold in the memory but stored to the disc
     * and only loaded when requested.
     * However a scaled pixbuf of the image is still needed for preview reasons.
     * Stored image will be removed from disc when item is removed from history.
     * To still be able to identify a picture, a md5 sum is built from the 
     * original pic.
     */
    public class ImageClipboardItem : GLib.Object, IClipboardItem
    {
        private ClipboardType _clipboard_type;
        private string _checksum; // check sum to identify pic content
        private Gdk.Pixbuf _pixbuf;
        private string _label;
        
        /**
         * Create image clipboard item by a pixbuf.
         * 
         * @param clipboard_type clipboard type item is coming from
         * @param pixbuf image from clipboard
         */
        public ImageClipboardItem.with_image(ClipboardType clipboard_type, Gdk.Pixbuf pixbuf) throws GLib.Error
        {
            _clipboard_type = clipboard_type;
            extract_pixbuf_info(pixbuf);
        }
        
        /**
         * Create image clipboard item by given payload.
         * 
         * @param clipboard_type clipboard type item is coming from
         * @param pixbuf image from clipboard
         */
        public ImageClipboardItem.with_payload(ClipboardType clipboard_type, ByteArray payload) throws GLib.Error
        {
            _clipboard_type = clipboard_type;
            // TODO implement
        }
    
        /**
	     * {@inheritDoc}
	     */
        public ClipboardType get_clipboard_type()
        {
            return _clipboard_type;
        }
        
        /**
	     * {@inheritDoc}
	     */
	    public string get_text()
        {
            return _label; // label is representation of image
        }

        /**
	     * {@inheritDoc}
	     */
        public string get_label()
        {
            return _label;
        }
        
        /**
	     * {@inheritDoc}
	     */
        public string get_mime_type()
        {
            // images are always converted to png
            return "image/png";
        }
        
        /**
	     * {@inheritDoc}
	     */
        public Icon get_icon()
        {
            // TODO niy
            //FileIcon icon = new FileIcon(File.new_for_path(_path));
            //return icon;
            return ContentType.get_icon(get_mime_type());
        }
        
        /**
	     * {@inheritDoc}
	     */
        public ClipboardCategory get_category()
        {
            return ClipboardCategory.IMAGES;
        }
        
        /**
	     * {@inheritDoc}
	     */
        public Gtk.Image? get_image()
        {
            Gdk.Pixbuf pixbuf_preview = create_scaled_pixbuf(_pixbuf);
            return new Gtk.Image.from_pixbuf(pixbuf_preview);
        }
        
        /**
	     * {@inheritDoc}
	     */
        public ByteArray? get_payload()
        {
            // TODO not implemented yet
            return null;
        }
        
        /**
         * {@inheritDoc}
         */
        public string get_checksum()
        {
            return _checksum;
        }
        
        /**
	     * {@inheritDoc}
	     */
        public void to_clipboard(Gtk.Clipboard clipboard)
        {
             clipboard.set_image(_pixbuf);
             clipboard.store();
        }
        
        /**
	     * {@inheritDoc}
	     */
        public bool matches(string search, ClipboardItemType type)
        {
            bool matches = false;
            
            if(type == ClipboardItemType.ALL
                || type == ClipboardItemType.IMAGES) {
                // we do not have any search to be matched
                // therefore only an empty search string matches
                matches = search.length == 0; 
            }
            
            return matches;
        }
        
        /**
	     * {@inheritDoc}
	     */
	    public bool equals(IClipboardItem* item)
        {
            bool equals = false;
            
            if(item is ImageClipboardItem) {
                ImageClipboardItem* image_item = (ImageClipboardItem*)item;
                equals = str_equal(_checksum, image_item->_checksum);
            }
            
            return equals;
        }
        
        /**
	     * {@inheritDoc}
	     */
	    public uint hash()
        {
            // use checksum to create hash code
            return str_hash(_checksum);
        }
        
        /**
         * Extracts all pixbuf information which are needed to show image
         * in the view without having the pixbuf in the memory.
         *
         * @param pixbuf pixbuf to extract info from
         */
        private void extract_pixbuf_info(Gdk.Pixbuf pixbuf)
        {
            // create md5 sum of picture
            Checksum checksum = new Checksum(ChecksumType.MD5);
            checksum.update(pixbuf.get_pixels(), pixbuf.height * pixbuf.rowstride);
            _checksum = checksum.get_string().dup();
            
            // label in format [{width}x{height}]
            _label ="[%dx%d]".printf(pixbuf.width, pixbuf.height); 
            _pixbuf = pixbuf;
        }
        
        /**
         * Create a menu icon size scaled pix buf
         *
         * @param pixbuf scaled pixbuf
         */
        private static Gdk.Pixbuf create_scaled_pixbuf(Gdk.Pixbuf pixbuf)
        {
            // get menu icon size
            Gtk.IconSize size = Gtk.IconSize.MENU;
            int width, height;
            if(!Gtk.icon_size_lookup(size, out width, out height)) {
                // set default when icon size lookup fails
                width = 16;
                height = 16;
            }
            
            // scale pixbuf to menu icon size
            Gdk.Pixbuf scaled = pixbuf.scale_simple(width, height, Gdk.InterpType.BILINEAR);
            return scaled;
        }
        
        /**
         * Store pixbuf to file system and return path to it.
         *
         * @param pixbuf pixbuf to be stored
         */
        private static string save_pixbuf(Gdk.Pixbuf pixbuf) throws GLib.Error
        {
            // create a file name in the diodon user data dir images folder
            string filename = "";
            string data_dir = Utility.get_user_data_dir();
            string image_data_dir = Path.build_filename(data_dir, "images");
            
            if(Utility.make_directory_with_parents(image_data_dir)) {
            
                // image file name equal timestamp in seconds
                // plus a random number in case when multiple images
                // are copied to a clipboard in one second
                int id = Random.int_range(1000, 9999);
                DateTime now = new DateTime.now_local();
                string name = now.format("%Y%m%d-%H%M%S") + "-%i.png".printf(id);
                
                filename = Path.build_filename(image_data_dir, name);
                pixbuf.save(filename, "png");
            }
        
            return filename;
        }
    }  
}

