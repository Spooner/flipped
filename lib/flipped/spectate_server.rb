require 'thread'
require 'socket'
require 'mutex_m'

require 'log'
require 'constants'
require 'message'
require 'spectator'

# =============================================================================
#
#
module Flipped
  class SpectateServer
    include Log
    
    DEFAULT_NAME = 'User'
    DEFAULT_TIME_LIMIT = 0
    
    protected
    def initialize(port)
      @port =  port

      srand

      @spectators = Array.new
      @spectators.extend(Mutex_m)
      
      @server = nil
      @listen_thread = nil

      # Frame messages received from the player, ready to send to
      # spectators and controller.
      @frames = Array.new
      @frames.extend(Mutex_m)

      @controller = nil
      @player = nil

      Thread.abort_on_exception = true

      listen

      nil
    end

    # ------------------------
    #
    #
    public
    def close
      @server.close unless @server.closed?

      @spectators.synchronize do
        @spectators.each { |s| s.close }
        @spectators.clear
      end

      nil
    end

    # Bring all spectators up to the current frame.
    protected
    def update_spectators
      log.info("Updating spectators")
      @spectators.synchronize do
        @spectators.dup.each do |spectator|
          # Update with all previous frames, except the player, who sends us frames.
          if spectator.logged_in? and not spectator.player?
            update_spectator(spectator)
          end
        end
      end
      
      nil
    end

    protected
    def update_spectator(spectator)
      @frames.synchronize do
        ((spectator.position + 1)...@frames.size).each do |i|
          log.info("Updating spectator ##{spectator.id}: #{spectator.name} (Frame ##{i + 1})")
          spectator.send(@frames[i])
        end
      end
    end

    # Called from the spectator itself.
    public
    def disconnect_spectator(spectator)
      return if @server.closed?

      message = Message::Disconnected.new(:id => spectator.id)
      @spectators.synchronize do
        @spectators.delete spectator
        @spectators.each do |other|
          other.send(message) if other.logged_in?
        end
      end

      nil
    end

    protected
    def wait_for_messages(spectator)
      Thread.new do
        log.info { "Started waiting for spectator messages..."}
        begin
          loop do
            case message = Message.read(spectator.socket)
              when Message::StoryNamed # Expected from Controller only
                @story_named = message

                @spectators.synchronize do
                  @spectators.each {|s| s.send(message) if s.logged_in? }
                end
                
              when Message::SiDStarted # Expected from Controller only
                @sid_started = message
                @player.send(message) if @player and @player.logged_in?

              when Message::Frame # Expected from Player only
                @frames.synchronize do
                  @frames.push message
                end

                update_spectators

              when Message::StoryStarted # Expected from Player only
                @story_started = message

                @spectators.synchronize do
                  @spectators.each {|s| s.send(message) if s.logged_in? }
                end

              when Message::Chat # Expected from anyone
                @spectators.synchronize do
                  target_id = message.to
                  if target_id
                    target = @spectators.find {|s| s.id == target_id }
                    target.send(message) if target
                  else
                    @spectators.each {|s| s.send(message) if s.logged_in? and s.id != spectator.id }
                  end
                end
                
              else
                log.error { "Unexpected message from controller: #{message.class}"}
            end
          end
        rescue IOError, SystemCallError => ex
          log.error { "Problem when waiting for controller messages."}
          log.error { ex }
          close
        end
      end
    end

    # Called from the spectator itself.
    public
    def connect_spectator(spectator)
      case spectator.role
        when :player
          @player = spectator

        when :controller
          @controller = spectator
      end

      begin
        spectator.send(Message::Accept.new)

        message = Message::Connected.new(:name => spectator.name, :id => spectator.id, :role => spectator.role, :time_limit => spectator.time_limit)
        spectator.send(message) # Remind them about themselves first.
        @spectators.synchronize do
          @spectators.each do |other|
            if other.logged_in?
              # Make sure everyone else knows about the newly connected spectator.
              other.send(message)
              # Make sure the newly connected spectator knows about everyone already logged in.
              spectator.send(Message::Connected.new(:name => other.name, :id => other.id, :role => other.role, :time_limit => other.time_limit))
            end
          end

          spectator.send(@story_named) if @story_named
          spectator.send(@story_started) if @story_started

          if spectator.player?
            spectator.send(@sid_started) if defined? @sid_started
          else
            update_spectator(spectator)
          end
        end
      rescue IOError, SystemCallError => ex
        log.error { "Failed to connect spectator."}
        log.error { ex }
        close
      end

      wait_for_messages(spectator)

      nil
    end

    #
    #
    protected
    def listen
      begin
        @server = TCPServer.new(@port)
      rescue IOError, SystemCallError => ex
        log.error(ex)
        raise Exception.new("#{self.class} failed to start on port #{@port}!")
      end

      log.info { "#{@name} waiting for a connection on port #{@port}." }

      @listen_thread = Thread.new do
        begin
          while socket = @server.accept
            add_spectator(socket)
          end
        rescue IOError, SystemCallError => ex
          log.error { "Failed to listen."}
          log.error { ex }
          close
        end
      end

      nil
    end

    # Add a new spectator associated with a particular socket.
    protected
    def add_spectator(socket)
      Thread.new(socket) do |socket|
        begin
          spectator = Spectator.new(self, socket)

          @spectators.synchronize do
            log.info { "Spectator connected from #{socket.addr[3]}:#{socket.addr[1]}." }
            @spectators.push spectator
          end
        rescue => ex
          # socket.addr can fail, apparently.
          log.error { ex }
        end
      end
    end
  end          
end