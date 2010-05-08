require 'fox16'

require 'book'

module Flipped
  include Fox

  class Gui < FXMainWindow
    APPLICATION = "Flipped"
    WINDOW_TITLE = "#{Flipped} - The SiD flip-book tool"

    IMAGE_WIDTH = 640
    IMAGE_HEIGHT = 416
    THUMB_SCALE = 0.25
    THUMB_WIDTH = IMAGE_WIDTH * THUMB_SCALE
    THUMB_HEIGHT = IMAGE_HEIGHT * THUMB_SCALE
    DEFAULT_SLIDE_SHOW_INTERVAL = 5000

    NAV_BUTTON_OPTIONS = { :opts => Fox::BUTTON_NORMAL|Fox::LAYOUT_CENTER_X|Fox::LAYOUT_FIX_WIDTH|Fox::LAYOUT_FIX_HEIGHT,
                           :width => 90, :height => 50 }

    DEFAULT_WINDOW_WIDTH = 800
    DEFAULT_WINDOW_HEIGHT = 800

    HELP_TEXT = <<END_TEXT
#{APPLICATION} is a flip-book tool for SleepIsDeath (http://sleepisdeath.net).

Author: Spooner (Bil Bas)

Features:
  - Open flipbooks and view them manually or as a slideshow.
  - Append flip-books to create longer books that can be saved.
  - Delete frames (right click on the thumbnail)

END_TEXT

    def initialize(app)
      super(app, WINDOW_TITLE, :opts => DECOR_ALL,
             :width => DEFAULT_WINDOW_WIDTH, :height => DEFAULT_WINDOW_HEIGHT)

      FXToolTip.new(getApp(), TOOLTIP_NORMAL)
      
      create_menu

      @main_frame = FXVerticalFrame.new(self, LAYOUT_FILL_X|LAYOUT_FILL_Y)

      # Sunken border for image widget
      @thumbs_window = FXScrollWindow.new(@main_frame, LAYOUT_FIX_HEIGHT|LAYOUT_FILL_X, :height => THUMB_HEIGHT + 50)
      @thumbs_column = FXHorizontalFrame.new(@thumbs_window,
        FRAME_SUNKEN|FRAME_THICK|LAYOUT_FIX_X|LAYOUT_FILL_Y,
        :padLeft => 0, :padRight => 0, :padTop => 0, :padBottom => 0,
        :width => THUMB_WIDTH)

      @image_viewer = FXImageView.new(@main_frame, :opts => LAYOUT_FILL_X|LAYOUT_FILL_Y)
      @image_viewer.connect(SEL_LEFTBUTTONPRESS, method(:right_button_pressed))

      @label = FXLabel.new(@main_frame, 'No flip-book loaded', nil, LAYOUT_FILL_X,
         :padLeft => 4, :padRight => 4, :padTop => 4, :padBottom => 4)

      add_button_bar(@main_frame)

      @thumb_viewers = []

      @current_directory = ''
      @current_frame_index = 0
      @playing = false

      @slide_show_interval = DEFAULT_SLIDE_SHOW_INTERVAL

      @book = Book.new
    end

    def create_menu
      menu_bar = FXMenuBar.new(self, LAYOUT_SIDE_TOP|LAYOUT_FILL_X|FRAME_RAISED)

      # File menu
      file_menu = FXMenuPane.new(self)
      FXMenuTitle.new(menu_bar, "&File", nil, file_menu)

      @open_menu = FXMenuCommand.new(file_menu, "&Open flip-book...\tCtl-O\tOpen flip-book.", nil).connect(SEL_COMMAND, method(:on_cmd_open))

      @append_menu = FXMenuCommand.new(file_menu, "A&ppend flip-book...\tCtl-P\tAppend flip-book to currently loaded flip-book.", nil).connect(SEL_COMMAND, method(:on_cmd_append))

      FXMenuSeparator.new(file_menu)

      @save_menu = FXMenuCommand.new(file_menu, "&Save flip-book...\tCtl-S\tSave current flip-book.", nil).connect(SEL_COMMAND, method(:on_cmd_save))

      FXMenuSeparator.new(file_menu)

      FXMenuCommand.new(file_menu, "&Quit\tCtl-Q").connect(SEL_COMMAND, method(:on_cmd_quit))

      # Options menu.
      options_menu = FXMenuPane.new(self)
      FXMenuTitle.new(menu_bar, "&Options", nil, options_menu)
      @toggle_thumbs_menu = FXMenuCheck.new(options_menu, "Show &Thumbnails...\tCtl-T\tHide/show thumbnail strip.", nil).connect(SEL_COMMAND, method(:on_toggle_thumbs))

      # Help menu
      help_menu = FXMenuPane.new(self)
      FXMenuTitle.new(menu_bar, "&Help", nil, help_menu, LAYOUT_RIGHT)

      FXMenuCommand.new(help_menu, "&About #{APPLICATION}...").connect(SEL_COMMAND) do
        help_dialog = FXMessageBox.new(self, "About #{APPLICATION}",
          HELP_TEXT, nil,
          MBOX_OK|DECOR_TITLE|DECOR_BORDER)
        help_dialog.execute
      end
    end

    def on_toggle_thumbs(sender, sel, ptr)
      if sender.checked?
        @thumbs_window.show
      else
        @thumbs_window.hide
      end
      @main_frame.recalc
    end

    def add_button_bar(window)
      button_bar = FXHorizontalFrame.new(window, :opts => LAYOUT_FILL_X)

      @start_button = FXButton.new(button_bar, '<<<', NAV_BUTTON_OPTIONS)
      @start_button.connect(SEL_LEFTBUTTONPRESS, method(:start_button_pressed))
      @start_button.disable
      @start_button.tipText = "Skip to first frame"

      @left_button = FXButton.new(button_bar, '<', NAV_BUTTON_OPTIONS)
      @left_button.connect(SEL_LEFTBUTTONPRESS, method(:left_button_pressed))
      @left_button.disable
      @left_button.tipText = "Previous frame"

      @play_button = FXButton.new(button_bar, '|>', NAV_BUTTON_OPTIONS)
      @play_button.connect(SEL_LEFTBUTTONPRESS, method(:play_button_pressed))
      @play_button.disable
      @play_button.tipText = "Play slide-show"

      @right_button = FXButton.new(button_bar, '>', NAV_BUTTON_OPTIONS)
      @right_button.connect(SEL_LEFTBUTTONPRESS, method(:right_button_pressed))
      @right_button.disable
      @right_button.tipText = "Next frame"

      @end_button = FXButton.new(button_bar, '>>>', NAV_BUTTON_OPTIONS)
      @end_button.connect(SEL_LEFTBUTTONPRESS, method(:end_button_pressed))
      @end_button.disable
      @end_button.tipText = "Skip to last frame"
    end

    # Convenience function to construct a PNG icon.
    def show_frames(selected = 0)
      @thumb_viewers.each do |viewer|
        @thumbs_column.removeChild(viewer)
      end
      @thumb_viewers.clear

      @book.frames.each_with_index do |frame, i|
        packer = FXVerticalFrame.new(@thumbs_column)
        image_view = FXImageView.new(packer, :opts => LAYOUT_FIX_WIDTH|LAYOUT_FIX_HEIGHT,
                                      :width => THUMB_HEIGHT, :height => THUMB_HEIGHT)

        image_view.connect(SEL_LEFTBUTTONPRESS, method(:on_thumb_left_click))
        image_view.connect(SEL_RIGHTBUTTONPRESS, method(:on_thumb_right_click))

        label = FXLabel.new(packer, "#{i + 1}", :opts => LAYOUT_FILL_X)

        packer.create

        @thumb_viewers.push packer      
        
        img = FXPNGImage.new(getApp(), frame, IMAGE_KEEP|IMAGE_SHMI|IMAGE_SHMP)
        img.create
        img.scale(THUMB_WIDTH, THUMB_HEIGHT)
        img.crop((THUMB_WIDTH - THUMB_HEIGHT) / 2, 0, THUMB_HEIGHT, THUMB_HEIGHT)

        image_view.image = img
      end

      select_frame(selected)

      nil
    end

    def start_button_pressed(sender, sel, ptr)
      select_frame(0)

      return 1
    end

    def left_button_pressed(sender, sel, ptr)
      select_frame(@current_frame_index - 1)

      return 1
    end

    def play_button_pressed(sender, sel, ptr)
      @playing = !@playing

      @play_button.disable
      if @playing
        @play_button.enable
        @slide_show_timer = getApp().addTimeout(@slide_show_interval, method(:slide_show_timer))
        @play_button.text = '||'
        @play_button.tipText = "Pause slide-show"
      else
        @play_button.text = '|>'      
        @play_button.tipText = "Play slide-show"
      end

      return 1
    end

    def slide_show_timer(sender, sel, ptr)

      if @playing
        select_frame(@current_frame_index + 1)
        if @current_frame_index < @book.size - 1
          @slide_show_timer = getApp().addTimeout(@slide_show_interval, method(:slide_show_timer))
        else
          @playing = false
          @play_button.text = '|>'
        end        
      end

      return 1
    end

    def right_button_pressed(sender, sel, ptr)
      select_frame([@current_frame_index + 1, @book.size - 1].min)

      return 1
    end

    def end_button_pressed(sender, sel, ptr)
      select_frame(@book.size - 1)

      return 1
    end

    def select_frame(index)
      @current_frame_index = index
      img = FXPNGImage.new(getApp(), @book[@current_frame_index], IMAGE_KEEP|IMAGE_SHMI|IMAGE_SHMP)
      img.create
      @image_viewer.image = img

      @label.text = "Frame #{index + 1} of #{@book.size}"

      @start_button.disable
      @left_button.disable

      @right_button.disable
      @end_button.disable

      if index > 0
        @start_button.enable unless @start_button.enabled
        @left_button.enable unless @left_button.enabled
      end

      if index < @book.size - 1
        @play_button.enable
        @end_button.enable
        @right_button.enable
      end

      nil
    end

    # Event when clicking on a thumbnail - select.
    def on_thumb_left_click(sender, sel, ptr)
      index = @thumb_viewers.index(sender.parent)
      select_frame(index)

      return 1
    end

    # Event when clicking on a thumbnail - delete.
    # TODO: Open up a menu.
    def on_thumb_right_click(sender, sel, ptr)
      index = @thumb_viewers.index(sender.parent)
      @book.delete_at(index)
      show_frames([index, @book.size - 1].min)

      return 1
    end

    # Open a new flip-book
    def on_cmd_open(sender, sel, ptr)
      open_dir = FXFileDialog.getOpenDirectory(self, "Open flip-book directory", @current_directory)
      begin
        getApp().beginWaitCursor do
          @book = Book.new(open_dir)
          show_frames
        end
        @current_directory = open_dir
      rescue => ex
        puts ex.class, ex, ex.backtrace.join("\n")
        dialog = FXMessageBox.new(self, "Open error!",
                 "Failed to load flipbook from #{open_dir}, probably because it is not a flipbook directory.", nil,
                 MBOX_OK|DECOR_TITLE|DECOR_BORDER)
        dialog.execute
      end

      return 1
    end

    # Open a new flip-book
    def on_cmd_append(sender, sel, ptr)
      open_dir = FXFileDialog.getOpenDirectory(self, "Append flip-book directory", @current_directory)
      begin
        getApp().beginWaitCursor do
          @book.append(Book.new(open_dir))
          show_frames
        end
        @current_directory = open_dir
      rescue => ex
        puts ex.class, ex, ex.backtrace.join("\n")
        dialog = FXMessageBox.new(self, "Open error!",
                 "Failed to load flipbook from #{open_dir}, probably because it is not a flipbook directory", nil,
                 MBOX_OK|DECOR_TITLE|DECOR_BORDER)
        dialog.execute
      end

      return 1
    end

    # Save this flip-book
    def on_cmd_save(sender, sel, ptr)
      save_dir = FXFileDialog.getSaveFilename(self, "Save flip-book directory", @current_directory)
      if File.exists? save_dir
        dialog = FXMessageBox.new(self, "Save error!",
                 "File/folder #{save_dir} already exists, so flip-book cannot be saved.", nil,
                 MBOX_OK|DECOR_TITLE|DECOR_BORDER)
        dialog.execute
      else
        @current_directory = save_dir
        @book.write(@current_directory, '../test_data/templates')
      end

      return 1
    end

    # Quit the application
    def on_cmd_quit(sender, sel, ptr)
      # Write new window size back to registry
      getApp().reg().writeIntEntry("SETTINGS", "x", x)
      getApp().reg().writeIntEntry("SETTINGS", "y", y)
      getApp().reg().writeIntEntry("SETTINGS", "width", width)
      getApp().reg().writeIntEntry("SETTINGS", "height", height)

      # Current directory
      #getApp().reg().writeStringEntry("SETTINGS", "directory", @file_list.directory)

      # Quit
      getApp().exit(0)
    end

    def create
      # Get size, etc. from registry
      xx = getApp().reg().readIntEntry("SETTINGS", "x", 0)
      yy = getApp().reg().readIntEntry("SETTINGS", "y", 0)
      ww = getApp().reg().readIntEntry("SETTINGS", "width", DEFAULT_WINDOW_WIDTH)
      hh = getApp().reg().readIntEntry("SETTINGS", "height", DEFAULT_WINDOW_HEIGHT)

      #dir = getApp().reg().readStringEntry("SETTINGS", "directory", "~")
           
      # Reposition window to specified x, y, w and h
      position(xx, yy, ww, hh)

      # Create and show
      super   # i.e. FXMainWindow::create()
      show(PLACEMENT_SCREEN)
    end
  end
end