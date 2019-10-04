require "se/api"
require "chatx"
require 'uri'
require 'logger'
require 'time'
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

sleeptime = 0

def main()
  setup_db("db/db.sqlite3")

  settings = File.exists?('./settings.yml') ? YAML.load_file('./settings.yml') : ENV
  bot_names = settings['names'] || Array(settings['name'])

  #setup Rooms in DB
  settings['rooms'].each do |room_id|
    Room.find_or_create_by(room_id: room_id)
  end

  #@logger = Logger.new('msg.log')

  chatter = Chatter.new(settings["ChatXUsername"], settings["ChatXPassword"], settings["hq_room_id"].to_i, settings["rooms"])
  seclient = SEClient.new(settings["APIKey"], settings["site"])
  scanner = CommentScanner.new(seclient, chatter, settings["all_comments"], perspective_key: settings['perspective_key'], perspective_log: Logger.new('perspective.log'))
  commander = Commander.new(chatter, seclient, scanner, bot_names)
  replier = Replier.new(chatter, seclient, scanner, bot_names)

  commander.setup_basic_commands()
  commander.setup_HQ_commands()
  replier.setup_reply_actions()
  replier.setup_mention_actions()

  @post_on_startup = ARGV[0].to_i || 0

  #TODO: Use this to get cats:
  # require 'httparty'
  # HTTParty.post("https://aws.random.cat/meow").parsed_response.first.second
end

main


#chatter.add_command_action(chatter.HQroom, "!!/first") do
#  chatter.say("No *I'm* first.", chatter.HQroom)
#end
#chatter.add_reply_action("tp") do | msg, args |
#  puts msg.hash
#  puts args
#  chatter.say("Beep boop you think you know more about comments than me? Wrong.", msg.hash["room_id"])
#end


#cli = SE::API::Client.new(settings['APIKey'], site: settings['site'])

#HQ_ROOM_ID = settings['hq_room_id'].to_i
#ROOMS = settings['rooms']
#IGNORE_USER_IDS = Array(settings['ignore_user_ids'] || WhitelistedUser.all.map(&:user_id))
#BOT_NAMES = settings['names'] || Array(settings['name'])
#def matches_bot(bot)
  #puts "Checking if #{bot} matches #{BOT_NAMES}"
  #bot.nil? || bot == '*' || BOT_NAMES.include?(bot.downcase)
#end

#def restart(num_to_post, bundle)
  #if bundle == "true"
    #say "Updating bundle..."
    #log = `bundle install`
    #say "Update complete!\n#{"="*32}\n#{log}"
  #end
  #Kernel.exec("bundle exec ruby comment_scan.rb #{num_to_post.nil? ? @post_on_startup : num_to_post.to_i}")
#end

#ROOMS.each do |room_id|
  #Room.find_or_create_by(room_id: room_id)
#end

#cb.gen_hooks do
  #on 'reply' do |msg, room_id|
    #begin
      #if msg.hash.include? 'parent_id'
        #mc_comment = MessageCollection::ALL_ROOMS.comment_for(msg.hash['parent_id'].to_i)
        #hg_comment = MessageCollection::ALL_ROOMS.howgood_for(msg.hash['parent_id'].to_i)
        #comment = mc_comment
        #if !comment.nil?
          #comment = Comment.find_by(comment_id: comment.id) if comment.is_a? SE::API::Comment
          #reply_args = msg.body.split(' ')
          #case reply_args[1].downcase
          #when 'tp'
            #comment.tps ||= 0
            #comment.tps += 1
            #cb.say "Marked this comment as caught correctly (tp). Currently marked #{comment.tps.to_i}tps/#{comment.fps.to_i}fps. *beep boop* My human overlords won't let me flag that, so you'll have to do it yourself.", room_id
          #when 'fp'
            #comment.fps ||= 0
            #comment.fps += 1
            #cb.say "Marked this comment as caught incorrectly (fp). Currently marked #{comment.tps.to_i}tps/#{comment.fps.to_i}fps", room_id
          #when 'wrongo'
            #comment.fps ||= 0
            #comment.fps += 1
            #cb.say "Registered as WRONGO! Currently marked #{comment.tps.to_i}tps/#{comment.fps.to_i}fps", room_id
          #when 'rude'
            #comment.rude ||= 0
            #comment.rude += 1
            #cb.say "Registered as rude. *beep boop* My human overlords won't let me flag that, so you'll have to do it yourself.", room_id
          #when 'i'
            ## Do nothing. This is for making comments about the comment
          #when 'dbid'
            #cb.say "This comment has id #{comment.id} in the database", room_id
          #when 'feedbacks'
            #cb.say "Currently marked #{comment.tps.to_i}tps/#{comment.fps.to_i}fps", room_id
          #when 'del'
            #MessageCollection::ALL_ROOMS.message_ids_for(mc_comment)[3..-1].each do |msg_id|
              #cb.delete(msg_id)
            #end
          #when 'huh?'
            #matched_regexes = report_raw(comment["post_type"], comment["body_markdown"])
            ## Go through regexes we matched to build reason_text
            #reason_text = matched_regexes.map do |regex_match|
              #reason = "Matched reason \"#{regex_match.reason.name}\""
              #regex = "for regex #{regex_match.regex}"
              #"#{reason} #{regex}"
            #end.join("\n")

            ## If post isn't deleted, check if this was an inactive comment
            #if post = post_exists?(cli, comment.post_id)
              #if timestamp_to_date(post.json["last_activity_date"]) < timestamp_to_date(comment["creation_date"]) - 30
                #reason_text += "Comment was made #{(timestamp_to_date(comment["creation_date"]) - timestamp_to_date(post.json["last_activity_date"])).to_i} days after last activity on post\n"
              #end
            #end

            #reason_text += "\nComment has toxicity of #{comment["perspective_score"]}" if comment["perspective_score"].to_f >= 0.7

            #cb.say (reason_text.empty? ? "Comment didn't match any regexes" : reason_text), room_id
          #when 'rescan'
            #c = cli.comments(comment["comment_id"])
            #if c.empty?
              #cb.say "Comment with id #{comment["comment_id"]} was deleted and cannot be rescanned.", room_id
            #else
              #scan_comments(c, cli:cli, settings:settings, cb:cb)
            #end
          #else
            #if reply_args.length > 2 #They're not trying to give a command
              ##Maybe make conversation back (33% chance)
              #cb.say ":#{msg.id} #{random_response}", room_id if rand() > 0.67
            #else
              #cb.say "Invalid feedback type. Valid feedback types are tp, fp, rude, and wrongo", room_id
            #end
          #end
          #comment.save
        #elsif !hg_comment.nil?
          #regex = hg_comment[0]
          #types = hg_comment[1]

          #params_passed = msg.body.downcase.split(' ')
          #num_to_display = 3
          #if params_passed.count >= 3
            #if !/\A\d+\z/.match(params_passed[2]) || params_passed[2].to_i < 1
              #cb.say "Bad number. Reply to howgood with <comment_type> <num> to print num matches of comment_type where comment types are tp, fp, and *", room_id
              #next
            #end
            #num_to_display = params_passed[2].to_i
          #end

          #comments_to_display = []

          #case params_passed[1]
          #when 'tp'
            #if types == '*'
              #comments_to_display = Comment.where("tps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            #else
              #comments_to_display = Comment.where(post_type: types).where("tps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            #end
          #when 'fp'
            #if types == '*'
              #comments_to_display = Comment.where("fps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            #else
              #comments_to_display = Comment.where(post_type: types).where("fps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            #end
          #when '*'
            #if types == '*'
              #comments_to_display = Comment.select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            #else
              #comments_to_display = Comment.where(post_type: types).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            #end
          ## when 'none'
          ### TODO: Would love to have this functionality, but for whatever reason this condition always matches nothing. Need to bug crestmaster about this.
          ###        That being said I'll probably pull request first and then figure this out as an add on...
          ##
          ##   if types == '*'
          ##     comments_to_display = Comment.where("fps < ?", 1).where("tps < ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
          ##   else
          ##     comments_to_display = Comment.where(post_type: type).where("fps < ?", 1).where("tps < ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
          ##   end
          #else
            #cb.say "Invalid comment type. Reply to howgood with <comment_type> <num> to print num matches of comment_type where comment types are tp, fp, and *", room_id
            #next
          #end

          #if comments_to_display.count == 0
            #cb.say "There are no " + params_passed[1] + "'s on that howgood.", room_id
            #next
          #end

          ## puts "Got passed: " + params_passed.to_s
          ## puts "Howgood with Regex: " + regex.to_s
          ## puts "Howgood with Types: " + types.to_s
          ## puts "Found the list of comments to display:"
          ## puts
          ## puts comments_to_display.take(num_to_display).to_s

          ## Pull comment_id's from the first num_to_display comments we matched to pass to scan
          #comments_to_display.take(num_to_display).each {
            #|comment|
            #report_comments(comment, cli: cli, settings: settings, cb: cb, should_post_matches: false)
          #}
        #else
          #puts "That was not a report"
          ## cb.say "That was not a report", room_id
        #end
      #end
    #rescue Exception => e
      #cb.say "Got excpetion ```#{e}``` processing your response", room_id
    #end
  #end
#end

#comments = cli.comments[0..-1]

#@last_creation_date = comments[@post_on_startup].json["creation_date"].to_i+1 unless comments[@post_on_startup].nil?

#sleep 1 # So we don't get chat errors for 3 messages in a row

#loop do
  #comments = cli.comments(fromdate: @last_creation_date)
  #@last_creation_date = comments[0].json["creation_date"].to_i+1 unless comments[0].nil?
  #scan_comments(comments, cli: cli, settings: settings, cb: cb)
  #sleeptime = 60
  #while sleeptime > 0 do sleep 1; sleeptime -= 1 end
#end
