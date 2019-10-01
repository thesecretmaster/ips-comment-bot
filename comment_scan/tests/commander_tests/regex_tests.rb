require "test/unit"

require_relative '../../commander'
require_relative '../mock_chatter'
 
class  RegexTest < Test::Unit::TestCase
    def setup
        #DB setup...
        setup_db("db/test_db.sqlite3")
        wipe_db

        #Setup chatter/commander
        @chatter = MockChatter.new(1)
        @commander = Commander.new(@chatter, ['testbot', '@testbot'])

        @commander.setup_basic_commands()
        @commander.setup_HQ_commands()

        #TODO: Going to need to fake a CLI for this test (for stuff like manscan)
    end

    def teardown
        #Wipe test_db after test
        wipe_db
    end

end