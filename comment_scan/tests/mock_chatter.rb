require './db'

class MockChatter
    attr_reader :HQroom, :rooms, :chats

    def initialize(num_child_rooms, logger)
        @logger = logger
        @HQroom = 0
        @rooms = [*1..num_child_rooms.to_i].map { |x| (x+100) }

        @reply_actions = {}
        @command_actions = {}
        @chats = {}

        @rooms ||= []
        (@rooms + [@HQroom]).each do |room_id|
            r = Room.find_or_create_by(room_id: room_id) #setup defaults in db
            r.turn_on
            r.update(regex_match: true)
            r.save

            @command_actions[room_id] = {}
            @chats[room_id] = []
        end
    end

    def add_command_action(room_id, command, action, args_to_pass=nil)
        @command_actions[room_id][command] = [action, args_to_pass]
    end

    def add_reply_action(reply, action, args_to_pass=nil)
        @reply_actions[reply] ||= []
        @reply_actions[reply] << [action, args_to_pass]
    end

    def simulate_message(room_id, message)
        prefix = message.downcase.strip.split(" ")[0]
        args = message.scan(%r{\"(.*)\"|\'(.*)\'|([^\s]*)}).flatten.reject { |a| a.to_s.empty? }[1..-1]

        begin
            @command_actions[room_id][prefix][0].call(*@command_actions[room_id][prefix][1], room_id, *args) if @command_actions[room_id].key?(prefix)
            @logger.debug "Called #{prefix} logic on #{@command_actions[room_id][prefix][0]}" if @command_actions[room_id].key?(prefix)
            @logger.debug "Called with (#{@command_actions[room_id][prefix][1].join(', ')}, #{room_id}, #{args.join(', ')})" if @command_actions[room_id].key?(prefix)
        rescue ArgumentError => e
            say("Invalid number of arguments for '#{prefix}' command.", room_id)
            #TODO: Would be cool to have some help text print here. Maybe we could pass it when we do add_command_action?
        end
    end

    def simulate_reply(room_id, parent_msg_id, message, userid="9999")
        #@reply_actions[args[0]].call(msg_id, parent_msg_id, room_id, *args) if @reply_actions.key?(args[0])

        #Grab/create/update chat user
        chat_user = ChatUser.find_or_create_by(user_id: userid)
        chat_user.update(name: "Mock User #{userid}")

        reply_args = message.downcase.split(' ')
        return if reply_args.length == 0 #No args
        reply_command = reply_args[0]
        reply_args = reply_args.drop(1) #drop the command

        @logger.debug "Got reply with command: #{reply_command}"
        @logger.debug "Does it exist? #{@reply_actions.key?(reply_command)}"
        if @reply_actions.key?(reply_command)
            @logger.debug @reply_actions[reply_command]
            begin
                @reply_actions[reply_command].each do |action, args_to_pass|
                    #                         vvvvv Pass fake message id (only used for replies)
                    action.call(*args_to_pass, 666, parent_msg_id, chat_user, room_id, *reply_args)
                end
            rescue ArgumentError => e
                say("Invalid number of arguments for '#{reply_command[0]}' command.", room_id)
                @logger.warn e
                #TODO: Would be cool to have some help text print here. Maybe we could pass it when we do add_command_action?
            rescue Exception => e
                say("Got exception ```#{e}``` processing your response", room_id)
            end
        else
            #@fall_through_actions.each { |action, payload| action.call(*payload, message.id, message.hash['parent_id'], room_id, *reply_args)}
        end
    end

    #A "ping" is any @ followed by 3+ word characters
    def say_pingless(message, room=@HQroom)
        #Replace all ping @'s with *'s
        say(message.gsub(/\@(\w{3})/, '*\1'), room)
    end

    def say(message, room=@HQroom)
        @chats[room] << message
        return @chats[room].length - 1 #Return index we just inserted
    end
end
