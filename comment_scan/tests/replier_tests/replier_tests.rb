require 'test/unit'
require './db'

require_relative '../../comment_scanner'
require_relative '../../replier'
require_relative '../../commander'
require_relative '../mock_chatter'
require_relative '../mock_client'

class  ReplierTest < Test::Unit::TestCase
    def setup
        #DB setup...
        setup_db("db/test_db.sqlite3")
        wipe_db

        @bot_names = ['testbot', '@testbot']

        #Setup chatter/commander
        @chatter = MockChatter.new(1)
        @client = MockClient.new()

        @scanner = CommentScanner.new(@client, @chatter, true, [])
        @commander = Commander.new(@chatter, nil, nil, @bot_names)
        @replier = Replier.new(@chatter, @client, @scanner, @bot_names)

        @commander.setup_HQ_commands() #don't really care about basics here
        @replier.setup_reply_actions()
        #@replier.setup_mention_actions()
        #@replier.setup_fall_through_actions()
    end

    def teardown
        #Wipe test_db after test
        wipe_db
    end

    def test_tp
        secomment = @client.new_comment("question", "I'm a new comment!")
        @scanner.scan_new_comments
        dbcomment = MessageCollection::ALL_ROOMS.comment_for(0) #grab that comment
        tps_before = dbcomment.tps.to_i
        fps_before = dbcomment.fps.to_i
        rudes_before = dbcomment.rude.to_i

        @chatter.simulate_reply(@chatter.HQroom, 0, "tp")

        assert(@chatter.chats[@chatter.HQroom][-1].include? "#{tps_before + 1}tps/#{fps_before}fps")
        assert_equal(tps_before + 1, dbcomment.tps.to_i, "Comment not updated in db correctly")
        assert_equal(fps_before, dbcomment.fps.to_i, "Comment not updated in db correctly")
        assert_equal(rudes_before, dbcomment.rude.to_i, "Comment not updated in db correctly")
    end

    def test_fp
        secomment = @client.new_comment("question", "I'm a new comment!")
        @scanner.scan_new_comments
        dbcomment = MessageCollection::ALL_ROOMS.comment_for(0) #grab that comment
        tps_before = dbcomment.tps.to_i
        fps_before = dbcomment.fps.to_i
        rudes_before = dbcomment.rude.to_i

        @chatter.simulate_reply(@chatter.HQroom, 0, "fp")

        assert(@chatter.chats[@chatter.HQroom][-1].include? "#{tps_before}tps/#{fps_before + 1}fps")
        assert_equal(tps_before, dbcomment.tps.to_i, "Comment not updated in db correctly")
        assert_equal(fps_before + 1, dbcomment.fps.to_i, "Comment not updated in db correctly")
        assert_equal(rudes_before, dbcomment.rude.to_i, "Comment not updated in db correctly")
    end

    def test_rude
        secomment = @client.new_comment("question", "I'm a new comment!")
        @scanner.scan_new_comments
        dbcomment = MessageCollection::ALL_ROOMS.comment_for(0) #grab that comment
        tps_before = dbcomment.tps.to_i
        fps_before = dbcomment.fps.to_i
        rudes_before = dbcomment.rude.to_i

        @chatter.simulate_reply(@chatter.HQroom, 0, "rude")

        assert(@chatter.chats[@chatter.HQroom][-1].include? "rude")
        assert_equal(tps_before + 1, dbcomment.tps.to_i, "Comment not updated in db correctly")
        assert_equal(fps_before, dbcomment.fps.to_i, "Comment not updated in db correctly")
        assert_equal(rudes_before + 1, dbcomment.rude.to_i, "Comment not updated in db correctly")
    end

    def test_feedbacks_across_different_rooms
        @chatter.simulate_message(@chatter.HQroom, "!!/add #{@bot_names[0]} q comment because_reasons") #ensure it'll be printed in all rooms
        secomment = @client.new_comment("question", "I'm a new comment!")
        @scanner.scan_new_comments

        dbcomment = MessageCollection::ALL_ROOMS.comment_for(0) #grab that comment
        tps_before = dbcomment.tps.to_i
        fps_before = dbcomment.fps.to_i
        rudes_before = dbcomment.rude.to_i

        @chatter.simulate_reply(@chatter.rooms[0], 0, "tp")
        @chatter.simulate_reply(@chatter.HQroom, 0, "feedbacks")

        assert(@chatter.chats[@chatter.HQroom][-1].include? "#{tps_before + 1}tps/#{fps_before}fps")
        assert_equal(tps_before + 1, dbcomment.tps.to_i, "Comment not updated in db correctly")
        assert_equal(fps_before, dbcomment.fps.to_i, "Comment not updated in db correctly")
        assert_equal(rudes_before, dbcomment.rude.to_i, "Comment not updated in db correctly")
    end

    def test_rescan
        @chatter.simulate_message(@chatter.HQroom, "!!/add #{@bot_names[0]} q comment because_reasons") #ensure it'll be printed in all rooms
        secomment = @client.new_comment("question", "I'm a new comment!")
        @scanner.scan_new_comments

        @chatter.simulate_reply(@chatter.HQroom, 0, "rescan")

        #One extra here for adding the regex
        assert_equal(7, @chatter.chats[@chatter.HQroom].length, "Incorrect number of messages posted to HQ")
        @chatter.rooms.each do |room_id|
            assert_equal(6, @chatter.chats[room_id].length, "Incorrect number of messages posted to child room")
        end
    end

    def test_custom_report
        secomment = @client.new_comment("question", "I'm a new comment!")
        @scanner.scan_new_comments
        custom_reason = "testing things"

        @chatter.simulate_reply(@chatter.HQroom, 0, "report #{custom_reason}")

        #Two extra here for the initial report
        assert_equal(5, @chatter.chats[@chatter.HQroom].length, "Incorrect number of messages posted to HQ")
        @chatter.rooms.each do |room_id|
            assert_equal(3, @chatter.chats[room_id].length, "Incorrect number of messages posted to child room")
        end

        (@chatter.rooms + [@chatter.HQroom]).each do |room_id|
            assert(@chatter.chats[room_id][-1].include? custom_reason)
        end
    end

end