require "chatx"
require "htmlentities"

class Chatter
    attr_reader :HQroom, :rooms

    def initialize(chatXuser, chatXpwd, hqroom, logger, rooms)
        @logger = logger

        @chatbot = ChatBot.new(chatXuser, chatXpwd, log_location: STDOUT, log_formatter: @logger.formatter)
        @HQroom = hqroom.to_i
        @rooms = rooms - [@HQroom] #Don't include HQ room in rooms

        @chatbot.login(cookie_file: 'cookies.yml')
        @chatbot.say("_Starting at rev #{`git rev-parse --short HEAD`.chop} on branch #{`git rev-parse --abbrev-ref HEAD`.chop} (#{`git log -1 --pretty=%B`.gsub("\n", '')})_", @HQroom)
        @chatbot.join_room @HQroom
        @chatbot.join_rooms @rooms # THIS IS THE PROBLEM

        @reply_actions = Hash.new { |hash, key| hash[key] = [] } #Automagically create an array for each new key
        @command_actions = {}
        @mention_actions = [] 
        @fall_through_actions = [] 

        #TODO: mention_received logic will be run alongside both command and reply logic. Going to need to fix this at some point
        (@rooms + [@HQroom]).each do |room_id|
            @command_actions[room_id] = {}

            @chatbot.add_hook(room_id, 'message') do |message|
                message_received(room_id, message)
            end

            @chatbot.add_hook(room_id, 'reply') do |message|
                #Treat replies as mentions, but only run if no reply actions were hit
                reply_received(room_id, message) || mention_received(room_id, message)
            end

            @chatbot.add_hook(room_id, 'mention') do |message|
                mention_received(room_id, message)
            end
        end
    end

    def add_command_action(room_id, command, action, args_to_pass=nil)
        @command_actions[room_id][command] = [action, args_to_pass]
    end

    def add_reply_action(reply, action, args_to_pass=nil)
        @reply_actions[reply] << [action, args_to_pass]
    end

    def add_mention_action(action, args_to_pass=nil)
        @mention_actions.push([action, args_to_pass])
    end

    def add_fall_through_reply_action(action, args_to_pass=nil)
        @fall_through_actions.push([action, args_to_pass])
    end

    def mention_received(room_id, message)
        #Grab/create/update chat user
        chat_user = ChatUser.find_or_create_by(user_id: message.hash['user_id'])
        chat_user.update(name: message.hash['user_name'])

        @mention_actions.each do |action, payload|
            #Run at most one mention action successfully
            return true if action.call(*payload, message.id, chat_user, room_id, message.body)
        end
        return false
    end

    def reply_received(room_id, message)
        return unless message.hash.include? 'parent_id'

        #Grab/create/update chat user
        chat_user = ChatUser.find_or_create_by(user_id: message.hash['user_id'])
        chat_user.update(name: message.hash['user_name'])

        reply_args = message.body.downcase.split(' ').drop(1) #Remove the reply portion
        return false if reply_args.empty? #No args
        reply_command = reply_args[0]
        reply_args = reply_args.drop(1) #drop the command

        if @reply_actions.key?(reply_command)
            begin
                reply_responses = @reply_actions[reply_command].map do |action, args_to_pass|
                    action.call(*args_to_pass, message.id, message.hash['parent_id'], chat_user, room_id, *reply_args)
                end
                return reply_responses.any? #return true if any responses got run
            rescue ArgumentError => e
                say("Invalid number of arguments for '#{reply_command[0]}' command.", room_id)
                @logger.warn e
                #TODO: Would be cool to have some help text print here. Maybe we could pass it when we do add_reply_action?
            rescue Exception => e
                say("Got exception ```#{e}``` processing your response", room_id)
            end
            return true
        else
            @fall_through_actions.each do |action, payload|
                action.call(*payload, message.id, message.hash['parent_id'], chat_user, room_id, *reply_args)
            end
            return false
        end
    end

    def message_received(room_id, message)
        #                                        strip &zwnj;
        msg = HTMLEntities.new.decode(message.content).remove("\u200C").remove("\u200B")
        prefix = msg.downcase.strip.split(" ")[0]
        args = msg.scan(%r{\"(.*)\"|\'(.*)\'|([^\s]*)}).flatten.reject { |a| a.to_s.empty? }[1..-1]

        begin
            @command_actions[room_id][prefix][0].call(*@command_actions[room_id][prefix][1], room_id, *args) if @command_actions[room_id].key?(prefix)
        rescue ArgumentError => e
            say("Invalid number of arguments for '#{prefix}' command.", room_id)
            @logger.warn e
            #TODO: Would be cool to have some help text print here. Maybe we could pass it when we do add_command_action?
        rescue Exception => e
            say("Got exception ```#{e}``` processing your command", room_id)
        end
    end

    def say(message, room=@HQroom)
        @chatbot.say(message, room)
    end

    def delete(message_id)
        @chatbot.delete(message_id)
    end

    private :message_received, :reply_received
end
