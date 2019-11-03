require 'test/unit'
require './db'

require_relative '../../comment_scanner'
require_relative '../../commander'
require_relative '../mock_chatter'
require_relative '../mock_client'

class ScannerTest < Test::Unit::TestCase
    def setup
        #DB setup...
        setup_db("db/test_db.sqlite3")
        wipe_db

        @logger = Logger.new(STDOUT, level: Logger::ERROR, formatter: proc { |severity, datetime, progname, msg| "#{msg}\n" })

        #Setup chatter/commander
        @chatter = MockChatter.new(1, @logger)
        @client = MockClient.new(@logger)

        @scanner = CommentScanner.new(@client, @chatter, true, [], @logger)
        @commander = Commander.new(@chatter, @client, @scanner, ['testbot', '@testbot'], @logger)

        @commander.setup_HQ_commands #don't really care about basics here
    end

    def teardown
        #Wipe test_db after test
        wipe_db
    end

    def test_scan_question_comment
        secomment = @client.new_comment("question", "I'm a new comment!")

        @scanner.scan_se_comment(secomment)

        assert_equal(2, @chatter.chats[@chatter.HQroom].length, "Comment was not posted to HQroom")
        assert(@chatter.rooms.all? { |room| @chatter.chats[room].length == 0 }) #Make sure comment wasn't posted to other rooms
    end

    def test_scan_deleted_comment
        test_body = "I'm a new comment!"
        secomment = @client.new_comment("question", test_body)
        dbcomment = Comment.record_comment(secomment, @logger, perspective_score: 0)
        @client.delete_comment(secomment.id)
        
        @scanner.scan_comment_from_db(dbcomment.id)

        assert_equal(2, @chatter.chats[@chatter.HQroom].length, "Comment was not posted to HQroom")
        #Since the comment is deleted, we should be posting the body instead of a link
        assert(@chatter.chats[@chatter.HQroom][0].include?(test_body))
        assert(@chatter.rooms.all? { |room| @chatter.chats[room].length == 0 }) #Make sure comment wasn't posted to other rooms
    end

    def test_scan_new
        secomment = @client.new_comment("question", "I'm a new comment!")

        @scanner.scan_new_comments

        assert_equal(2, @chatter.chats[@chatter.HQroom].length, "Comment was not posted to HQroom")
        assert(@chatter.rooms.all? { |room| @chatter.chats[room].length == 0 }) #Make sure comment wasn't posted to other rooms
    end

    def test_scan_last_comments
        [*1..4].each { |num| @client.new_comment("question", "I'm a new comment ##{num}!") }

        @scanner.scan_last_n_comments(3)

        assert_equal(6, @chatter.chats[@chatter.HQroom].length, "Not all comments posted to HQroom")
        assert(@chatter.rooms.all? { |room| @chatter.chats[room].length == 0 }) #Make sure comment wasn't posted to other rooms
    end

    def test_regex_matches
        test_regex = "blargl"
        test_reason = "blargl_reason"
        test_body = "I'm a #{test_regex} comment"
        @chatter.simulate_message(@chatter.HQroom, "!!/add testbot q #{test_regex} #{test_reason}") 
        secomment = @client.new_comment("question", test_body)

        @scanner.scan_new_comments

        #           vvv  5 here because the !!/add command will generate 2
        assert_equal(5, @chatter.chats[@chatter.HQroom].length, "Regex match was not posted to HQroom")
        assert(@chatter.chats[@chatter.HQroom][-1].include?(test_reason))
        assert(@chatter.rooms.all? { |room| @chatter.chats[room].length == 3 }) #Make sure comment *was* posted to other rooms
    end

    def test_scan_from_db_doesnt_post
        test_regex = "blargl"
        test_reason = "blargl_reason"
        test_body = "I'm a #{test_regex} comment"
        @chatter.simulate_message(@chatter.HQroom, "!!/add testbot q #{test_regex} #{test_reason}") 
        secomment = @client.new_comment("question", test_body)
        dbcomment = Comment.record_comment(secomment, @logger, perspective_score: 0)

        @scanner.scan_comment_from_db(dbcomment.id)

        #           vvv  5 here because the !!/add command will generate 2
        assert_equal(5, @chatter.chats[@chatter.HQroom].length, "Regex match was not posted to HQroom")
        assert(@chatter.chats[@chatter.HQroom][-1].include?(test_reason))
        assert(@chatter.rooms.all? { |room| @chatter.chats[room].length == 0 }) #Make sure comment wasn't posted to other rooms
    end

end
