require "chatx"
require "htmlentities"

class Chatter
    attr_reader :HQroom, :rooms

    def initialize(chatXuser, chatXpwd, hqroom, *rooms)
        if ENV['SHORT_LOGS']
          $stdout.sync = true #Do we really need this??
          log_formatter = proc do |severity, datetime, progname, msg|
            "#{msg}\n"
          end
        else
          log_formatter = nil
        end

        @chatbot = ChatBot.new(chatXuser, chatXpwd, log_location: STDOUT, log_formatter: log_formatter)
        @HQroom = hqroom.to_i
        @rooms = rooms - [@HQroom] #Don't include HQ room in rooms

        @chatbot.login(cookie_file: 'cookies.yml')
        @chatbot.say("_Starting at rev #{`git rev-parse --short HEAD`.chop} on branch #{`git rev-parse --abbrev-ref HEAD`.chop} (#{`git log -1 --pretty=%B`.gsub("\n", '')})_", @HQroom)
        @chatbot.join_room @HQroom
        @chatbot.join_rooms @rooms # THIS IS THE PROBLEM

        @reply_actions = Hash.new()
        @command_actions = Hash.new()

        (@rooms + [@HQroom]).each do |room_id|
            @command_actions[room_id] = Hash.new()

            @chatbot.add_hook(room_id, 'message') do |message|
                message_received(room_id, message)
            end

            @chatbot.add_hook(room_id, 'reply') do |message|
                reply_received(room_id, message)
            end
        end
    end

    def add_command_action(room_id, command, action, args_to_pass=nil)
        @command_actions[room_id][command] = [action, args_to_pass]
    end

    def add_reply_action(reply, &action)
        @reply_actions[reply] = action
    end

    def reply_received(room_id, message)
        reply_args = message.body.downcase.split(' ').drop(1) #Remove the reply portion
        return if reply_args.length == 0 #No args
        reply_command = reply_args[0]
        @reply_actions[reply_command].call(message.id, message.hash['parent_id'], message.hash['room_id'], reply_args) if @reply_actions.key?(reply_command)
    end

    def message_received(room_id, message)
        #For debugging
        #puts "Got message #{message.hash}"
        #puts "with contents \"#{message.content}\""
        #puts "In room: \"#{message.hash['room_id']}\""
        #puts "Commands are: "
        #puts @command_actions

        #                                        strip &zwnj;
        msg = HTMLEntities.new.decode(message.content).remove("\u200C").remove("\u200B")
        prefix = msg.downcase.strip.split(" ")[0]
        args = msg.scan(%r{\"(.*)\"|\'(.*)\'|([^\s]*)}).flatten.reject { |a| a.to_s.empty? }[1..-1]

        begin
            @command_actions[room_id][prefix][0].call(*@command_actions[room_id][prefix][1], room_id, *args) if @command_actions[room_id].key?(prefix)
        rescue ArgumentError => e
            say("Invalid number of arguments for '#{prefix}' command.", room_id)
            #TODO: Would be cool to have some help text print here. Maybe we could pass it when we do add_command_action?
        end
    end

    def say(message, room)
        @chatbot.say(message, room)
    end

    private :message_received, :reply_received
end