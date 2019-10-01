class MockChatter
    attr_reader :HQroom, :rooms, :chats

    def initialize(num_child_rooms)
        @HQroom = "HQ Baby"
        @rooms = [*1..num_child_rooms.to_i].map {|x| "room#{x}"}

        @reply_actions = Hash.new()
        @command_actions = Hash.new()
        @chats = Hash.new()

        @rooms ||= []
        (@rooms + [@HQroom]).each do |room_id|
            @command_actions[room_id] = Hash.new()
            @chats[room_id] = []
        end
    end

    def add_command_action(room_id, command, action, args_to_pass=nil)
        @command_actions[room_id][command] = [action, args_to_pass]
    end

    def add_reply_action(room_id, message)
        @reply_actions[reply] = action
    end

    def simulate_message(room_id, message)
        prefix = message.downcase.strip.split(" ")[0]
        args = message.scan(%r{\"(.*)\"|\'(.*)\'|([^\s]*)}).flatten.reject { |a| a.to_s.empty? }[1..-1]

        begin
            @command_actions[room_id][prefix][0].call(*@command_actions[room_id][prefix][1], room_id, *args) if @command_actions[room_id].key?(prefix)
        rescue ArgumentError => e
            say("Invalid number of arguments for '#{prefix}' command.", message.hash['room_id'])
            #TODO: Would be cool to have some help text print here. Maybe we could pass it when we do add_command_action?
        end
    end

    def reply_received(room_id, args, parent_msg_id, msg_id:)
        @reply_actions[args[0]].call(msg_id, parent_msg_id, room_id, *args) if @reply_actions.key?(args[0])
    end

    def say(message, room)
        @chats[room] << message
    end
end