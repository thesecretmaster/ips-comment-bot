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
        #Client and scanner won't be used for these tests, so pass nil's (for now)
        @commander = Commander.new(@chatter, nil, nil, ['testbot', '@testbot'])

        @commander.setup_basic_commands()
        @commander.setup_HQ_commands()

        #TODO: Going to need to fake a CLI for this test (for stuff like manscan)
    end

    def teardown
        #Wipe test_db after test
        wipe_db
    end

    def test_add_regex_new_reason_q
        test_regex = 'regex'
        test_reason = 'reason'

        @chatter.simulate_message(@chatter.HQroom, "!!/add testbot q #{test_regex} #{test_reason}")

        assert_equal(1, Regex.where(post_type: 'q', regex: test_regex).length, "Regex was not added.")
        assert_equal(1, Reason.where(name: test_reason).length, "Reason was not added.")
        assert_equal(Regex.where(post_type: 'q', regex: test_regex)[0].reason_id, Reason.where(name: test_reason)[0].id, "Regex was not properly linked to reason.")
    end

    def test_add_regex_new_reason_a
        test_regex = 'regex'
        test_reason = 'reason'

        @chatter.simulate_message(@chatter.HQroom, "!!/add testbot a #{test_regex} #{test_reason}")

        assert_equal(1, Regex.where(post_type: 'a', regex: test_regex).length, "Regex was not added.")
        assert_equal(1, Reason.where(name: test_reason).length, "Reason was not added.")
        assert_equal(Regex.where(post_type: 'a', regex: test_regex)[0].reason_id, Reason.where(name: test_reason)[0].id, "Regex was not properly linked to reason.")
    end

    def test_add_multiword_reason
        test_regex = 'regex'
        test_reason = 'multi word reason'

        @chatter.simulate_message(@chatter.HQroom, "!!/add testbot a #{test_regex} #{test_reason}")

        assert_equal(1, Regex.where(post_type: 'a', regex: test_regex).length, "Regex was not added.")
        assert_equal(1, Reason.where(name: test_reason).length, "Reason was not added.")
        assert_equal(Regex.where(post_type: 'a', regex: test_regex)[0].reason_id, Reason.where(name: test_reason)[0].id, "Regex was not properly linked to reason.")
    end

    def test_add_malformed_regex
        test_regex = 'malformed(regex'
        test_reason = 'reason'

        @chatter.simulate_message(@chatter.HQroom, "!!/add testbot a #{test_regex} #{test_reason}")

        assert(@chatter.chats[@chatter.HQroom].any? { |chat| chat.downcase.include? "invalid" }) #, "Error message not displayed")
        assert_equal(0, Regex.where(post_type: 'a', regex: test_regex).length, "Regex was incorrectly added.")
        assert_equal(0, Reason.where(name: test_reason).length, "Reason was incorrectly added.")
    end

    def test_del_regex_not_reason
        test_regex1 = 'regex1'
        test_regex2 = 'regex2'
        test_reason = 'reason'

        @chatter.simulate_message(@chatter.HQroom, "!!/add testbot a #{test_regex1} #{test_reason}")
        @chatter.simulate_message(@chatter.HQroom, "!!/add testbot a #{test_regex2} #{test_reason}")

        @chatter.simulate_message(@chatter.HQroom, "!!/del testbot a #{test_regex1}")

        assert_equal(0, Regex.where(post_type: 'a', regex: test_regex1).length, "Regex was not deleted.")
        assert_equal(1, Regex.where(post_type: 'a', regex: test_regex2).length, "Regex was incorrectly deleted.")
        assert_equal(1, Reason.where(name: test_reason).length, "Reason was incorrectly deleted.")
    end

    def test_del_regex_AND_reason
        test_regex = 'regex'
        test_reason = 'reason'

        @chatter.simulate_message(@chatter.HQroom, "!!/add testbot a #{test_regex} #{test_reason}")
        @chatter.simulate_message(@chatter.HQroom, "!!/del testbot a #{test_regex}")

        assert_equal(0, Regex.where(post_type: 'a', regex: test_regex).length, "Regex was not deleted.")
        assert_equal(0, Reason.where(name: test_reason).length, "Reason was not deleted.")
    end

    def test_print_regexes
        # !!/regexes output usually already has the words "Reason" and "Regex", so had to get creative here
        test_regex = 'random_words'
        test_reason = 'what_do_i_even_put_here'

        @chatter.simulate_message(@chatter.HQroom, "!!/add testbot a #{test_regex} #{test_reason}")
        @chatter.simulate_message(@chatter.HQroom, "!!/regexes testbot")

        assert([test_regex, test_reason].all? { |str| @chatter.chats[@chatter.HQroom][-1].include? str }) #, "Regex reported incorrectly")
    end

end