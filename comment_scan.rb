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
require_relative 'comment_scan/commander'

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

  chatter = Chatter.new(settings["ChatXUsername"], settings["ChatXPassword"], settings["hq_room_id"].to_i, settings["rooms"])
  commander = Commander.new(chatter, bot_names)
  #replier = Replier.new(...) #Coming soon!

  commander.setup_basic_commands()
  commander.setup_HQ_commands()

  @post_on_startup = ARGV[0].to_i || 0
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

#@logger = Logger.new('msg.log')
#@perspective_log = Logger.new('perspective.log')

#def scan_comments(*comments, cli:, settings:, cb:, perspective_log: Logger.new('/dev/null'))
  #comments.flatten.each do |comment|

    #body = comment.json["body_markdown"]
    #toxicity = perspective_scan(body, perspective_key: settings['perspective_key']).to_f

    #if dbcomment = record_comment(comment, perspective_score: toxicity)
      ## MessageCollection::ALL_ROOMS.swap_key(comment, dbcomment)
      #report_comments(dbcomment,cli: cli, settings: settings, cb: cb, should_post_matches: true)
    #end

    ## if reasons.map(&:name).include?('abusive') || reasons.map(&:name).include?('offensive')
    ##   Thread.new do
    ##     sleep 60
    ##     msgs.each do |msg|
    ##       cb.delete(msg.to_i)
    ##     end
    ##   end
    ## end

    ## @logger.info "Parsed comment:"
    ## @logger.info "(JSON) #{comment.json}"
    ## @logger.info "(SE::API::Comment) #{comment.inspect}"
    ## @logger.info "Current time: #{Time.new.to_i}"

    ## rval = cb.say(comment.link, 63296)
    ## cb.delete(rval.to_i)
    ## cb.say(msg, 63296)

  #end
#end

#def report_comments(*comments, cli:, settings:, cb:, should_post_matches: true)
  #comments.flatten.each do |comment|

    #user =  Array(User.where(id: comment["owner_id"]).as_json)
    #user = user.any? ? user[0] : false # if user was deleted, set it to false for easy checking

    #puts "Grab metadata..."


    #author = user ? user["display_name"] : "(removed)"
    #author_link = user ? "[#{author}](#{user["link"]})" : "(removed)"
    #rep = user ? "#{user["reputation"]} rep" : "(removed) rep"

    #date = Time.at(comment["creation_date"].to_i)
    #seconds = (Time.new - date).to_i
    #ts = seconds < 60 ? "#{seconds} seconds ago" : "#{seconds/60} minutes ago"

    #puts "Grab post data/build message to post..."

    #msg = "##{comment["post_id"]} #{author_link} (#{rep})"

    #puts "Analyzing post..."

    #post_inactive = false # Default to false in case we can't access post
    #post = [] # so that we can use this later for whitelisted users

    #if post = post_exists?(cli, comment.post_id) # If post wasn't deleted, do full print
      #author = user_for post.owner
      #editor = user_for post.last_editor
      #creation_ts = ts_for post.json["creation_date"]
      #edit_ts = ts_for post.json["last_edit_date"]
      #type = post.type[0].upcase
      #closed = post.json["close_date"]

      #post_inactive = timestamp_to_date(post.json["last_activity_date"]) < timestamp_to_date(comment["creation_date"]) - 30

      #msg += " | [#{type}: #{post.title}](#{post.link}) #{'[c]' if closed} (score: #{post.score}) | posted #{creation_ts} by #{author}"
      #msg += " | edited #{edit_ts} by #{editor}" unless edit_ts.empty? || editor.empty?
    #end

    ## toxicity = perspective_scan(body, perspective_key: settings['perspective_key']).to_f
    #toxicity = comment["perspective_score"].to_f

    #puts "Building message..."
    #msg += " | Toxicity #{toxicity}"
    ## msg += " | Has magic comment" if !post_exists?(cli, comment["post_id"]) and has_magic_comment? comment, post
    #msg += " | High toxicity" if toxicity >= 0.7
    #msg += " | Comment on inactive post" if post_inactive
    #msg += " | tps/fps: #{comment["tps"].to_i}/#{comment["fps"].to_i}"

    #puts "Building comment body..."

    ## If the comment exists, we can just post the link and ChatX will do the rest
    ## Else, make a quote manually with just the body (no need to be fancy, this must be old)
    ## (include a newline in the manual string to lift 500 character limit in chat)
    ## TODO: Chat API is truncating to 500 characters right now even though we're good to post more. Fix this.
    #comment_text_to_post = isCommentDeleted(cli, comment["comment_id"]) ? ("\n> " + comment["body"]) : comment["link"]

    #puts "Check reasons..."

    #report_text = report(comment["post_type"], comment["body_markdown"])
    #reasons = report_raw(comment["post_type"], comment["body_markdown"]).map(&:reason)

    #if reasons.map(&:name).include?('abusive') || reasons.map(&:name).include?('offensive')
      #comment_text_to_post = "⚠️☢️\u{1F6A8} [Offensive/Abusive Comment](#{comment["link"]}) \u{1F6A8}☢️⚠️"
    #end

    #msgs = MessageCollection::ALL_ROOMS

    #puts "Post chat message..."

    #if settings['all_comments']
      #msgs.push comment, cb.say(comment_text_to_post, HQ_ROOM_ID)
      #msgs.push comment, cb.say(msg, HQ_ROOM_ID)
      #msgs.push comment, cb.say(report_text, HQ_ROOM_ID) if report_text
    ## To be totally honest, maintaining this is not worth it to me right now, so I'm gonna stop working on this setting
    ## elsif !settings['all_comments'] && (has_magic_comment?(comment, post) || report_text) && !IGNORE_USER_IDS.map(&:to_i).push(post.owner.id).flatten.include?(comment.owner.id.to_i)
    #elsif !settings['all_comments'] && (report_text) && (post && !IGNORE_USER_IDS.map(&:to_i).push(post.owner.id).flatten.include?(user["user_id"].to_i))
      #msgs.push comment, cb.say(comment_text_to_post, HQ_ROOM_ID)
      #msgs.push comment, cb.say(msg, HQ_ROOM_ID)
      #msgs.push comment, cb.say(report_text, HQ_ROOM_ID) if report_text
    #end

    #ROOMS.each do |room_id|
      #room = Room.find_by(room_id: room_id)
      #if room.on
        #should_post_message = (
                                ## (room.magic_comment && has_magic_comment?(comment, post)) ||
                                #(room.regex_match && report_text) ||
                                #toxicity >= 0.7 || # I should add a room property for this
                                #post_inactive # And this
                              #) && should_post_matches && user &&
                              #post && !IGNORE_USER_IDS.map(&:to_i).push(post.owner.id).map(&:to_i).include?(user["user_id"].to_i) &&
                              #(user['user_type'] != 'moderator')

        #if should_post_message
          #msgs.push comment, cb.say(comment_text_to_post, room_id)
          #msgs.push comment, cb.say(msg, room_id)
          #msgs.push comment, cb.say(report_text, room_id) if room.regex_match && report_text
        #end
      #end
    #end

  #end

  #puts "Processing complete!"

#end

#sleep 1 # So we don't get chat errors for 3 messages in a row

#loop do
  #comments = cli.comments(fromdate: @last_creation_date)
  #@last_creation_date = comments[0].json["creation_date"].to_i+1 unless comments[0].nil?
  #scan_comments(comments, cli: cli, settings: settings, cb: cb)
  #sleeptime = 60
  #while sleeptime > 0 do sleep 1; sleeptime -= 1 end
#end
