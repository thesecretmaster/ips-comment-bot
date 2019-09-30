require "test/unit"

require_relative '../commander'
require_relative 'mock_chatter'
 
class WhitelistTest < Test::Unit::TestCase
	def setup
		setup_db("db/test_db.sqlite3")
		wipe_db

		WhitelistedUser.create(user_id: '666')

		#Setup chatter/commander and db
		#puts MockChatter
		@chatter = MockChatter.new(0)
		@commander = Commander.new(@chatter, ['testbot', '@testbot'])

  		@commander.setup_basic_commands()
  		@commander.setup_HQ_commands()
	end

	def teardown
		#Wipe test_db after test
		wipe_db
	end

	def test_single_user_add_whitelist
		test_uid = '62'

		@chatter.simulate_message(@chatter.HQroom, "!!/whitelist testbot #{test_uid}")

		assert_equal(1, WhitelistedUser.where(user_id: test_uid).length, "User was not added to the Whitelist")
	end

	def test_multi_user_add_whitelist
		test_uids = ['62', '94', '577472']

		@chatter.simulate_message(@chatter.HQroom, "!!/whitelist testbot #{test_uids.join(" ")}")

		test_uids.each do |test_uid|
			assert_equal(1, WhitelistedUser.where(user_id: test_uid).length, "User was not added to the Whitelist")
		end
	end

	def test_single_user_remove_whitelist
		test_uid = '62'

		@chatter.simulate_message(@chatter.HQroom, "!!/whitelist testbot #{test_uid}")
		@chatter.simulate_message(@chatter.HQroom, "!!/unwhitelist testbot #{test_uid}")

		assert_equal(0, WhitelistedUser.where(user_id: test_uid).length, "User was not removed from the Whitelist")
	end

	def test_multi_user_remove_whitelist
		test_uids = ['62', '94', '577472']

		@chatter.simulate_message(@chatter.HQroom, "!!/whitelist testbot #{test_uids.join(" ")}")
		@chatter.simulate_message(@chatter.HQroom, "!!/unwhitelist testbot #{test_uids.join(" ")}")

		test_uids.each do |test_uid|
			assert_equal(0, WhitelistedUser.where(user_id: test_uid).length, "User was not removed from the Whitelist")
		end
	end

	def test_whitelisted
		test_uid = '976219873071'

		@chatter.simulate_message(@chatter.HQroom, "!!/whitelist testbot  #{test_uid}")
		@chatter.simulate_message(@chatter.HQroom, "!!/whitelisted testbot")

		assert(@chatter.chats[@chatter.HQroom][-1].include? test_uid)#, "Whitelist reported incorrectly")
	end

end