require 'thread'
require 'socket'

require 'log'
require 'spectate_server'
require 'message'

# =============================================================================
#
#
module Flipped
  class SpectateClient
    include Log
    
    DEFAULT_PORT = SpectateServer::DEFAULT_PORT
    DEFAULT_NAME = SpectateServer::DEFAULT_NAME
    DEFAULT_TIME_LIMIT = SpectateServer::DEFAULT_TIME_LIMIT
    DEFAULT_STORY_NAME = 'Story'

     # Time that the Player first received a frame [Time].
    attr_reader :story_started_at
    # Name that the Controller gave to the story [String].
    attr_accessor :story_name

    protected    
    def initialize(owner, address, port, name, role, time_limit)
      @owner, @address, @port, @name, @role, @time_limit = owner, address, port, name, role, time_limit

      @player, @controller = nil, nil
      @spectators = Array.new
      @story_started_at = nil
      @story_name = DEFAULT_STORY_NAME

      connect

      nil
    end

    public
    attr_reader :controller_name
    def controller_name # :nodoc:
      @controller ? @controller.name : DEFAULT_NAME
    end

    public
    attr_reader :controller_time_limit
    def controller_time_limit # :nodoc:
      @controller ? @controller.time_limit : DEFAULT_TIME_LIMIT
    end

    public
    attr_reader :player_name
    def player_name # :nodoc:
      @player ? @player.name : DEFAULT_NAME
    end

    public
    attr_reader :player_time_limit
    def player_time_limit # :nodoc:
      @player ? @player.time_limit : DEFAULT_TIME_LIMIT
    end

    public
    def closed?
      @socket.closed?
    end

    #
    #
    public
    def close
      @socket.close unless @socket.closed?

      nil
    end

    protected
    def read()
      @frames_buffer = []
      @frames_buffer.extend(Mutex_m)

      begin
        until @socket.closed?
          message = Message.read(@socket)
          case message
            when Message::Frame
              frame_data = message.frame
              log.info { "Received frame (#{frame_data.size} bytes)" }
              @owner.request_event(:on_frame_received, frame_data)

            when Message::Challenge
              log.info { "Server at #{@address}:#{@port} identified as #{@player_name}." }

              Message::Login.new(:name => @name, :role => @role, :time_limit => @time_limit, :version => VERSION).write(@socket)

            when Message::Accept
              log.info { "Login accepted" }
              if message.renamed_as
                @name = message.renamed_as
              end

              # If the controller has logged in, update everyone else with the name of the story.
              if @role == :controller and @story_name
                 Message::StoryNamed.new(:name => @story_name).write(@socket)
              end

            when Message::Connected
              case message.role
                when :controller
                  @controller = message
                  log.info { "Controller '#{@controller.name}' connected with #{@controller.time_limit}s turns." }
                when :player
                  @player = message
                  log.info { "Player '#{@player.name}' connected with #{@player.time_limit}s turns." }
                else
                  log.info { "Spectator '#{message.name}' connected." }
              end
              
              @spectators.push message

            when Message::Disconnected
              to_remove = @spectators.find {|s| s.id == message.id }
              @spectators.delete(to_remove)
              @controller = nil if to_remove.id == @controller.id
              @player = nil if to_remove.id == @player.id
              log.info { "Spectator '#{to_remove.name}' disconnected." }

            when Message::StoryNamed
              @story_name = message.name
              log.info { "Story named as '#{@story_name}'" }

            when Message::StoryStarted
              @story_started_at = message.started_at
              log.info { "Story '#{@story_name}' started at '#{@story_started_at}'" }
              @owner.request_event(:on_story_started, @story_name, @story_started_at)

            else
              log.error { "Unrecognised message type: #{message.class}" }
          end
        end
      rescue IOError, SystemCallError => ex
        log.error { "Failed to read message."}
        log.error { ex }
        close
      end

      nil
    end

    # ONLY ON THE PLAYER client.
    public
    def send_frames(frames)
      log.info { "Sending #{frames.size} frames to server."}

      begin
        frames.each do |frame|
          Message::Frame.new(:frame => frame).write(@socket)
        end
      rescue IOError, SystemCallError => ex
        log.error { "Failed to send frames."}
        log.error { ex }
        close
      end
      
      nil
    end

    # ONLY ON THE PLAYER client.
    public
    def send_story_started
      @story_started_at = Time.now
      message = Message::StoryStarted.new(:started_at => @story_started_at)

      begin
        message.write(@socket)
      rescue IOError, SystemCallError => ex
        log.error { "Failed to send story started."}
        log.error { ex }
        close
      end

      @story_started_at
    end

    #
    #
    protected
    def connect()
      @socket = TCPSocket.open(@address, @port)

      log.info { "Connected to #{@address}:#{@port}." }

      Thread.new { read }
      
      nil
    end
  end
end