require 'base64'
require 'json'
require 'time'

require 'log'

module Flipped
  # Abstract class, parent of all packets.
  class Message
    include Log
    
    JSON_CLASS = 'json_class'
    DEFAULT_NAME = 'User'

    # Class => {name => default, name => default, ...]
    @@value_defaults = Hash.new { |hash, key| hash[key] = {} }

    # Values are stored internally keyed by strings, but for the user they are symbols.
    # Boolean values are read via "value?()".
    protected
    def self.value(symbol, default)
      @@value_defaults[self][symbol] = default
      class_eval(<<-EOS, __FILE__, __LINE__)
        def #{symbol}#{[true, false].include?(default) ? '?' : ''}
          default = @@value_defaults[self.class][:#{symbol}]
          value = @values['#{symbol}']
          # Symbol values are converted back into symbols when read.
          value = value.to_sym if default.is_a?(Symbol) and value  
          value || default
        end
      EOS
    end

    protected
    def initialize(values = {})
      @values = Hash.new
      @@value_defaults[self.class].each_pair do |symbol, default|
        key = if values.has_key? JSON_CLASS
          symbol.to_s # Being re-constructed from a stream.
        else         
          symbol # Being initially created.
        end
        @values[symbol.to_s] = values[key] unless values[key] == default or values[key].nil?
      end
    end

    public
    def to_json(*args)
      @values.merge(JSON_CLASS => self.class.name).to_json(*args)
    end

    protected
    def self.json_create(message)
      new(message)
    end

    # Read the next message from a stream.
    #
    # === Parameters
    # +io+:: Stream from which to read a message.
    #
    # Returns message read [Message]
    public
    def self.read(io)
      json = io.gets
      raise IOError.new("Failed to read message") unless json
      
      log.debug { json }

      message = JSON.parse(json)
      log.info { "Received #{message.class} (#{json.size} bytes)." }

      message
    end

    # Write the message onto a stream.
    #
    # === Parameters
    # +io+:: Stream on which to write self.
    #
    # Returns the number of bytes written (not including the size header).
    public
    def write(io)
      json = to_json
      log.info { "Sending #{json.size} bytes." }
      log.debug { json }
      io.puts(json)

      json.size
    end

    public
    def ==(other)
      (other.class == self.class) and (other.instance_eval { @values } == @values)
    end

    # Sent by server in response to making a connection.
    class Challenge < Message
      include Log

      public
      def require_password?
        not self.password_seed.nil?
      end
      
      value :version, nil

      value :password_seed, nil # Not nil implies a password is requested.
    end

    # Sent by client to server in response to Challenge.
    class Login < Message
      include Log

      value :name, DEFAULT_NAME
      value :role, :spectator
      value :time_limit, nil
      value :version, nil

      value :password, nil # Sent only if password requested.
    end

    # Sent by server in response to Login.
    class Accept < Message
      include Log

      value :renamed_as, nil
    end

    # Sent by server in response to Login.
    class Reject < Message
      include Log
    end

    # Frame data.
    class Frame < Message
      include Log

      value :data, ''

      public
      attr_reader :frame
      def frame # :nodoc:
        Base64.decode64(@values['data'])
      end

      protected
      def initialize(values = {})
        super(:data => values[:frame] ? Base64.encode64(values[:frame]) : values['data'] )
      end
    end

    # Sent to the player when the controller starts up SiD.
    class SiDStarted < Message
      include Log
      
      value :port, nil
    end

    # Sent by server to tell the client to clear current book ready for a new story.
    class StoryStarted < Message
      include Log

      value :started_at, nil

      # Redefine started at so that time string is parsed back into a Time object.
      alias_method :started_at_OLD, :started_at
      public
      attr_reader :started_at
      def started_at # :nodoc:
        Time.parse(started_at_OLD)
      end
    end

    class StoryNamed < Message
      include Log
           
      value :name, 'Story'
    end

    # A spectator or controller has connected.
    class Connected < Message
      include Log

      public
      def controller?; self.role == :controller; end
      def player?; self.role == :player; end
      def spectator?; self.role == :spectator; end

      value :id, nil
      value :name, DEFAULT_NAME
      value :role, :spectator
      value :time_limit, nil
    end

    # A spectator or controller has disconnected.
    class Disconnected < Message
      include Log
      
      value :id, nil
    end

    # User changes her/his name.
    class Rename < Message
      include Log

      value :id, nil
      value :name, DEFAULT_NAME
    end

    # User chats to other users (or a specific user)
    class Chat < Message
      include Log

      value :from, nil # ID, player is #0.
      value :to, nil # ID, optional.
      value :text, nil
    end

    # Player kicks a controller/spectator after connection.
    class Kick < Message
      include Log
      
      value :id, nil # ID
      value :message, nil # Optional.
    end

    # Controller/spectator leaves.
    class Quit < Message
      include Log

      value :message, nil
    end
  end
end