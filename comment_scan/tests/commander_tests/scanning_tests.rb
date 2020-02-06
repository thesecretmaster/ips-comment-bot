require "test/unit"

require_relative '../../commander'
require_relative '../../comment_scanner'
require_relative '../mock_chatter'
require_relative '../mock_client'
 
class  RegexTest < Test::Unit::TestCase
    def setup
        @bot_name = 'testbot'
        #DB setup...
        setup_db("db/test_db.sqlite3")
        wipe_db

        @logger = Logger.new(STDOUT, level: Logger::ERROR, formatter: proc { |severity, datetime, progname, msg| "#{msg}\n" })

        #Setup chatter/commander
        @chatter = MockChatter.new(1, @logger)
        @client = MockClient.new(@logger)

        @scanner = CommentScanner.new(@client, @chatter, true, [], @logger)
        @commander = Commander.new(@chatter, @client, @scanner, [@bot_name], @logger)

        @commander.setup_basic_commands
        @commander.setup_HQ_commands

        #TODO: Going to need to fake a CLI for this test (for stuff like manscan)
    end

    def teardown
        #Wipe test_db after test
        wipe_db
        MessageCollection::ALL_ROOMS.clear
    end

    def test_scan_comments_with_bads
        bad_id = 99999
        test_body = "I'm a new comment!"
        secomment = @client.new_comment("question", test_body)
        dbcomment = Comment.record_comment(secomment, @logger, perspective_score: 0)
        #@scanner.scan_new_comments

        @chatter.simulate_message(@chatter.HQroom, "!!/manscan #{@bot_name} #{bad_id} #{secomment.id}")

        assert(@chatter.chats[@chatter.HQroom][0].include?("BAD ID"))
        assert_equal(3, @chatter.chats[@chatter.HQroom].length, "Comment was not posted to HQroom")
    end

end