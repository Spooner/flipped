require 'fox16'
include Fox

module Flipped
  class SpectateWindow < FXMainWindow

    class UserList < FXList
      class User < FXListItem
        attr_reader :role, :id, :name

        public
        def name=(name)
          @name = name

          self.text = case @role
            when :controller
              "#{name} (C)"
            when :player
              "#{name} (P)"
            else
              name
          end

          @list.sortItems

          name
        end

        public
        def role=(role)
          @role = role
          @list.set_role_icon(id, @role)
          
          role
        end

        public
        def create
          super
          @list.set_role_icon(id, @role)
        end

        protected
        def initialize(list, id, name, role)
          super('')
          @list = list
          @role = role
          @id = id          
          self.name = name

          nil
        end

        public
        def <=>(other)
          name.downcase <=> other.name.downcase
        end
      end

      # Get the user by id.
      public
      def [](id)
        find_user_by_id(id)
      end

      public
      def add_user(name, id, role)
        appendItem(User.new(self, name, id, role))
        sortItems

        nil
      end

      def remove_user(id)
        user = find_user_by_id(id)
        removeItem(user) if user

        nil
      end

      def find_user_by_id(id)
        each {|user| return user if user.id == id }
        nil
      end

      # Only for use by internal User class.
      public
      def set_role_icon(id, role)
        # TODO: set icon based on role
      end
    end

    # Translation strings.
    attr_reader :t

    protected
    def initialize(app, translations)
      @t = translations
      super(app, t.initial_title, :opts => (DECOR_ALL & ~DECOR_CLOSE), :x => 100, :y => 100, :width => 400, :height => 400)
      main_frame = FXSplitter.new(self, :opts => SPLITTER_TRACKING|LAYOUT_FILL)

      add_chat_frame(main_frame)

      add_user_frame(main_frame)

      @on_chat_input = nil # Handler for when local user enters a chat string.
      @player_id = nil # ID of the local player.

      nil
    end

    protected
    def add_chat_frame(frame)
      chat_frame = FXVerticalFrame.new(frame, :opts => LAYOUT_FILL_X|LAYOUT_FILL_Y)
      @chat_output = FXText.new(chat_frame, :opts => LAYOUT_FILL_X|LAYOUT_FILL_Y) do |widget|
        widget.editable = false      
      end      

      input_frame = FXHorizontalFrame.new(chat_frame, :opts => LAYOUT_FILL_X)

      @chat_input = FXTextField.new(input_frame, 1, :opts => TEXTFIELD_NORMAL|LAYOUT_FILL_X) do |widget|
        widget.connect(SEL_COMMAND, method(:chat_input_handler))
        widget.connect(SEL_CHANGED) do |sender, selector, text|
          @chat_send_button.enabled = (not text.empty?)
        end
      end

      @chat_send_button = Button.new(input_frame, t.send_button) do |widget|
        widget.enabled = false
        widget.connect(SEL_COMMAND, method(:chat_input_handler))
      end

      nil
    end

    protected
    def chat_input_handler(sender, selector, text)
      if @player_id and not sender.text.empty?
        @on_chat_input.call(@player_id, nil, text) if @on_chat_input
        chat(@player_id, nil, text)
        sender.text = ''
        @chat_send_button.enabled = false
      end
    end

    protected
    def add_user_frame(frame)
      user_frame = FXVerticalFrame.new(frame, :opts => LAYOUT_FILL_X|LAYOUT_FILL_Y|LAYOUT_FIX_WIDTH)
      @user_list = UserList.new(user_frame, :opts => LIST_SINGLESELECT|LAYOUT_FILL_X|LAYOUT_FILL_Y)

      nil
    end

    public
    def on_chat_input(method = nil, &block)
      @on_chat_input = block ? block : method

      nil
    end

    public
    def chat(from, to, text)
      name = @user_list[from].name
      if to
        puts t.message.whispers(name, text)
      else
        puts t.message.says(name, text)
      end

      nil
    end

    public
    def user_connected(id, name, role)
      if @player_id
        puts t.message.connected(name, t.role[role])
      else
        @player_id = id 
      end
      @user_list.add_user(id, name, role)

      nil
    end

    public
    def user_disconnected(id)
      puts t.message.disconnected(name)
      @user_list.remove_user(id)
      
      nil
    end

    public
    def advance_turn(index, name, time_limit)
      role = index.modulo(2) == 0 ? :controller : :player
      puts t.message.turn(index, name, t.role[role], time_limit, index + 1)

      nil
    end

    protected
    def puts(text)
      @chat_output.appendText("#{text}\n")
    end

    public
    def [](id)
      @user_list[id]

      nil
    end
  end
end