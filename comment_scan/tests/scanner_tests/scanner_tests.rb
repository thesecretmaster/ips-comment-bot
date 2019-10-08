require 'test/unit'

require_relative '../../comment_scanner'
require_relative '../mock_chatter'
require_relative '../mock_client'

class ScannerTest < Test::Unit::TestCase
    def setup
        #DB setup...
        setup_db("db/test_db.sqlite3")
        wipe_db

        #Setup chatter/commander
        @chatter = MockChatter.new(1)
        @client = MockClient.new()

        @scanner = CommentScanner.new(@client, @chatter, true, [])
    end

    def teardown
        #Wipe test_db after test
        wipe_db
    end

    def test_scan_question_comment
        secomment = @client.new_comment("question", "I'm a new comment!")

        @scanner.scan_se_comment(secomment)

        puts @chatter.chats
    end
end