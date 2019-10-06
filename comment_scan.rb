require 'logger'
require 'yaml'
require './db'
require 'pry-byebug'
  
require_relative 'comment_scan/message_collection'
require_relative 'comment_scan/helpers'
require_relative 'comment_scan/chatter'
require_relative 'comment_scan/seclient'
require_relative 'comment_scan/commander'
require_relative 'comment_scan/replier'
require_relative 'comment_scan/comment_scanner'

IO.write("bot.pid", Process.pid.to_s)

setup_db("db/db.sqlite3")

settings = File.exists?('./settings.yml') ? YAML.load_file('./settings.yml') : ENV
bot_names = settings['names'] || Array(settings['name'])
ignore_users = Array(settings['ignore_user_ids'] || WhitelistedUser.all.map(&:user_id))

#setup Rooms in DB
settings['rooms'].each do |room_id|
  Room.find_or_create_by(room_id: room_id)
end

chatter = Chatter.new(settings["ChatXUsername"], settings["ChatXPassword"], settings["hq_room_id"].to_i, settings["rooms"])
seclient = SEClient.new(settings["APIKey"], settings["site"])
scanner = CommentScanner.new(seclient, chatter, settings["all_comments"], ignore_users, perspective_key: settings['perspective_key'], perspective_log: Logger.new('perspective.log'))
commander = Commander.new(chatter, seclient, scanner, bot_names)
replier = Replier.new(chatter, seclient, scanner, bot_names)

commander.setup_basic_commands()
commander.setup_HQ_commands()
replier.setup_reply_actions()
replier.setup_mention_actions()
replier.setup_fall_through_actions()

sleep 1 # So we don't get chat errors for 3 messages in a row

post_on_startup = ARGV[0].to_i || 0
scanner.scan_last_n_comments(post_on_startup)

sleeptime = 0
loop do
  scanner.scan_new_comments

  sleeptime = 60
  while sleeptime > 0 do sleep 1; sleeptime -= 1 end
end


