require 'logger'
require 'yaml'
require './db'
require 'pry-byebug'
  
require_relative 'comment_scan/message_collection'
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

if ENV['SHORT_LOGS']
  $stdout.sync = true #Do we really need this??
  log_formatter = proc do |severity, datetime, progname, msg|
    "#{msg}\n"
  end
else
  log_formatter = nil
end

master_logger = Logger.new(STDOUT, level: Logger::DEBUG, formatter: log_formatter)

chatter = Chatter.new(settings["ChatXUsername"], settings["ChatXPassword"], 
                        settings["hq_room_id"].to_i, master_logger, settings["rooms"], settings["server"])
seclient = SEClient.new(settings["APIKey"], settings["site"], master_logger)
scanner = CommentScanner.new(seclient, chatter, settings["all_comments"], ignore_users,
                                master_logger, hot_secs: settings["hot_seconds"], hot_comment_num: settings["hot_comment_num"],
                                perspective_key: settings['perspective_key'],
                                perspective_log: Logger.new('perspective.log'))
commander = Commander.new(chatter, seclient, scanner, bot_names, master_logger)
replier = Replier.new(chatter, seclient, scanner, bot_names, master_logger)

commander.setup_basic_commands
commander.setup_HQ_commands
replier.setup_reply_actions
replier.setup_mention_actions
replier.setup_fall_through_actions

sleep 1 # So we don't get chat errors for 3 messages in a row

post_on_startup = ARGV[0].to_i || 0
scanner.scan_last_n_comments(post_on_startup)

loop do
  scanner.scan_new_comments
  sleep 1 while scanner.tick
end
