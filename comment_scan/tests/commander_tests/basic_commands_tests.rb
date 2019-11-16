require "test/unit"

require_relative '../../commander'
require_relative '../mock_chatter'
 
class BasicCommandsTest < Test::Unit::TestCase
    def setup
        #Give interesting names for whoami test
        @bot_names = ['testbot', '@testbot', 'some_random_str9193826']

        #DB setup...
        setup_db("db/test_db.sqlite3")
        wipe_db

        @logger = Logger.new(STDOUT, level: Logger::ERROR, formatter: proc { |severity, datetime, progname, msg| "#{msg}\n" })

        #Setup chatter/commander
        @chatter = MockChatter.new(1, @logger)
        #Client and scanner won't be used for these tests, so pass nil's
        @commander = Commander.new(@chatter, nil, nil, @bot_names, @logger)

        @commander.setup_basic_commands #Only need basics for this one
    end

    def teardown
        #Wipe test_db after test
        wipe_db
    end

    def test_alive
        @chatter.simulate_message(@chatter.HQroom, "!!/alive")

        assert_equal("I'm alive and well :)", @chatter.chats[@chatter.HQroom][0], "Bad alive message")
    end

    def test_help_HQ
        @chatter.simulate_message(@chatter.HQroom, "!!/help")

        assert(@chatter.chats[@chatter.HQroom][0].include?("!!/whitelisted")) #Check for HQ only command
    end

    def test_help_child
        @chatter.simulate_message(@chatter.rooms[0], "!!/help")

        assert(@chatter.chats[@chatter.rooms[0]][0].include?("!!/help")) #Meta is always best
        assert(!@chatter.chats[@chatter.rooms[0]][0].include?("!!/whitelisted")) #Make sure HQ only command doesn't exist
    end

    def test_mode_HQ
        @chatter.simulate_message(@chatter.HQroom, "!!/mode")

        assert(@chatter.chats[@chatter.HQroom][0].include?("I'm in parent mode."))
    end

    def test_mode_child
        @chatter.simulate_message(@chatter.rooms[0], "!!/mode")

        assert(@chatter.chats[@chatter.rooms[0]][0].include?("I'm in child mode."))
    end

    def test_notify_child
        room = Room.find_or_create_by(room_id: @chatter.rooms[0])
        room.update(regex_match: false)

        @chatter.simulate_message(@chatter.rooms[0], "!!/notify #{@bot_names[0]} regex on")

        assert_equal("I will notify you on a regex_match.", @chatter.chats[@chatter.rooms[0]][0], "Bad notify message")
        assert_equal(true, Room.find_or_create_by(room_id: @chatter.rooms[0]).regex_match, "db was not updated properly")
    end

    def test_off_child
        room = Room.find_or_create_by(room_id: @chatter.rooms[0])
        room.update(on: true)
        
        @chatter.simulate_message(@chatter.rooms[0], "!!/off")

        assert_equal("Turning off...", @chatter.chats[@chatter.rooms[0]][0], "Bad off message")
        assert_equal(false, Room.find_or_create_by(room_id: @chatter.rooms[0]).on?, "db was not updated properly")
    end

    def test_off_fail_child
        room = Room.find_or_create_by(room_id: @chatter.rooms[0])
        room.update(on: false) #already off
        
        @chatter.simulate_message(@chatter.rooms[0], "!!/off")

        assert_equal("I'm already off, silly", @chatter.chats[@chatter.rooms[0]][0], "Bad off message")
        assert_equal(false, Room.find_or_create_by(room_id: @chatter.rooms[0]).on?, "db was not updated properly")
    end

    def test_on_child
        room = Room.find_or_create_by(room_id: @chatter.rooms[0])
        room.update(on: false)
        
        @chatter.simulate_message(@chatter.rooms[0], "!!/on")

        assert_equal("Turning on...", @chatter.chats[@chatter.rooms[0]][0], "Bad on message")
        assert_equal(true, Room.find_or_create_by(room_id: @chatter.rooms[0]).on?, "db was not updated properly")
    end

    def test_on_fail_child
        room = Room.find_or_create_by(room_id: @chatter.rooms[0])
        room.update(on: true) #already on
        
        @chatter.simulate_message(@chatter.rooms[0], "!!/on")

        assert_equal("I'm already on, silly", @chatter.chats[@chatter.rooms[0]][0], "Bad on message")
        assert_equal(true, Room.find_or_create_by(room_id: @chatter.rooms[0]).on?, "db was not updated properly")
    end

    def test_reports_child
        room = Room.find_or_create_by(room_id: @chatter.rooms[0])
        room.update(regex_match: true) #setup regex_match reports

        @chatter.simulate_message(@chatter.rooms[0], "!!/reports")

        assert_equal("regex_match: true\nmagic_comment: false", @chatter.chats[@chatter.rooms[0]][0], "Bad reports message")
    end

    def test_whoami
        @chatter.simulate_message(@chatter.HQroom, "!!/whoami")

        assert_equal("I go by #{@bot_names.join(" and ")}", @chatter.chats[@chatter.HQroom][0], "Bad whoami message")
    end

end