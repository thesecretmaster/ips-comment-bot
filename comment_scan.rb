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

IO.write("bot.pid", Process.pid.to_s)

start = Time.now
sleeptime = 0

settings = File.exists?('./settings.yml') ? YAML.load_file('./settings.yml') : ENV

post_on_startup = ARGV[0].to_i || 0

cb = ChatBot.new(settings['ChatXUsername'], settings['ChatXPassword'])
cli = SE::API::Client.new(settings['APIKey'], site: settings['site'])
HQ_ROOM_ID = settings['hq_room_id'].to_i
ROOMS = settings['rooms']
IGNORE_USER_IDS = Array(settings['ignore_user_ids'] || WhitelistedUser.all.map(&:user_id))
cb.login(cookie_file: 'cookies.yml')
cb.say("_Starting at rev #{`git rev-parse --short HEAD`.chop} on branch #{`git rev-parse --abbrev-ref HEAD`.chop} (#{`git log -1 --pretty=%B`.gsub("\n", '')})_", HQ_ROOM_ID)
cb.join_room HQ_ROOM_ID
cb.join_rooms ROOMS #THIS IS THE PROBLEM
BOT_NAMES = settings['names'] || Array(settings['name'])
def matches_bot(bot)
  puts "Checking if #{bot} matches #{BOT_NAMES}"
  bot.nil? || bot == '*' || BOT_NAMES.include?(bot.downcase)
end

ROOMS.each do |room_id|
  Room.find_or_create_by(room_id: room_id)
end

cb.gen_hooks do
  on 'reply' do |msg, room_id|
    begin
      if msg.hash.include? 'parent_id'
        mc_comment = MessageCollection::ALL_ROOMS.comment_for(msg.hash['parent_id'].to_i)
        hg_comment = MessageCollection::ALL_ROOMS.howgood_for(msg.hash['parent_id'].to_i)
        comment = mc_comment
        if !comment.nil?
          comment = Comment.find_by(comment_id: comment.id) if comment.is_a? SE::API::Comment
          case msg.body.split(' ')[1].downcase
          when 'tp'
            comment.tps ||= 0
            comment.tps += 1
            cb.say "Marked this comment as caught correctly (tp). Currently marked #{comment.tps.to_i}tps/#{comment.fps.to_i}fps", room_id
          when 'fp'
            comment.fps ||= 0
            comment.fps += 1
            cb.say "Marked this comment as caught incorrectly (fp) Currently marked #{comment.tps.to_i}tps/#{comment.fps.to_i}fps", room_id
          when 'wrongo'
            comment.fps ||= 0
            comment.fps += 1
            cb.say "Registered as WRONGO", room_id
          when 'rude'
            comment.rude ||= 0
            comment.rude += 1
            cb.say "Registered as rude", room_id
          when 'i'
            # Do nothing. This is for making comments about the comment
          when 'dbid'
            cb.say "This comment has id #{comment.id} in the database", room_id
          when 'feedbacks'
            cb.say "Currently marked #{comment.tps.to_i}tps/#{comment.fps.to_i}fps", room_id
          when 'del'
            MessageCollection::ALL_ROOMS.message_ids_for(mc_comment)[3..-1].each do |msg_id|
              cb.delete(msg_id)
            end
          else
            cb.say "Invalid feedback type. Valid feedback types are tp, fp, rude, and wrongo", room_id
          end
          comment.save
        elsif !hg_comment.nil?
          regex = hg_comment[0]
          types = hg_comment[1]
         
          params_passed = msg.body.downcase.split(' ')
          num_to_display = 3
          if params_passed.count >= 3
            if !/\A\d+\z/.match(params_passed[2]) || params_passed[2].to_i < 1
              cb.say "Bad number. Reply to howgood with <comment_type> <num> to print num matches of comment_type where comment types are tp, fp, and *", room_id
              next
            end
            num_to_display = params_passed[2].to_i
          end
          
          comments_to_display = []
          
          case params_passed[1]
          when 'tp'
            if types == '*'
              comments_to_display = Comment.where("tps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            else
              comments_to_display = Comment.where(post_type: types).where("tps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            end
          when 'fp'
            if types == '*'
              comments_to_display = Comment.where("fps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            else
              comments_to_display = Comment.where(post_type: types).where("fps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            end
          when '*'
            if types == '*'
              comments_to_display = Comment.select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            else
              comments_to_display = Comment.where(post_type: types).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            end
          # when 'none'
          ## TODO: Would love to have this functionality, but for whatever reason this condition always matches nothing. Need to bug crestmaster about this.
          ##        That being said I'll probably pull request first and then figure this out as an add on...
          #
          #   if types == '*'
          #     comments_to_display = Comment.where("fps < ?", 1).where("tps < ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
          #   else
          #     comments_to_display = Comment.where(post_type: type).where("fps < ?", 1).where("tps < ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
          #   end
          else
            cb.say "Invalid comment type. Reply to howgood with <comment_type> <num> to print num matches of comment_type where comment types are tp, fp, and *", room_id
            next
          end
          
          if comments_to_display.count == 0
            cb.say "There are no " + params_passed[1] + "'s on that howgood.", room_id
            next
          end
            
          # puts "Got passed: " + params_passed.to_s
          # puts "Howgood with Regex: " + regex.to_s
          # puts "Howgood with Types: " + types.to_s
          # puts "Found the list of comments to display:"
          # puts
          # puts Array(comments_to_display.as_json).take(num_to_display).to_s
          
          #Pull comment_id's from the first num_to_display comments we matched to pass to scan
          Array(comments_to_display.as_json).take(num_to_display).each { 
            |comment| 
            report_comments(comment, cli: cli, settings: settings, cb: cb, should_post_matches: false)
          }
        else
          puts "That was not a report"
          # cb.say "That was not a report", room_id
        end
      end
    rescue Exception => e
      cb.say "Got excpetion ```#{e}``` trying to accept your feedback", room_id
    end
  end
  ROOMS.each do |room_id|
    room room_id do
      command "!!/off" do |bot|
        if matches_bot(bot) && on?(room_id)
          say "Turning off..."
          Room.find_by(room_id: room_id).update(on: false)
        end
      end
      command "!!/whoami" do
        if on?(room_id)
          say "I go by #{BOT_NAMES.join(" and ")}"
        end
      end
      command "!!/mode" do |bot|
        if matches_bot(bot) && on?(room_id)
          say "I'm in child mode. My parent is in [room #{HQ_ROOM_ID}](https://chat.stackexchange.com/rooms/#{HQ_ROOM_ID})"
        end
      end
      command "!!/on" do |bot|
        if matches_bot(bot) && !on?(room_id)
          say "Turning on..."
          Room.find_by(room_id: room_id).update(on: true)
        end
      end
      command "!!/notify" do |bot, type, status|
        if matches_bot(bot) && on?(room_id)
          act = {
                  "regex" => :regex_match,
                  "magic" => :magic_comment
                }[type]
          status = {"on" => true, "off" => false}[status]
          say "I #{status ? "will" : "won't"} notify you on a #{act}" unless status.nil? || act.nil?
          Room.find_by(room_id: room_id).update(**{act => status}) unless status.nil? || act.nil?
        end
      end
      command "!!/reports" do |bot|
        if matches_bot(bot) && on?(room_id)
          room = Room.find_by(room_id: room_id)
          say "regex_match: #{!!room.regex_match}\nmagic_comment: #{!!room.magic_comment}"
        end
      end
      command "!!/alive" do |bot|
        if matches_bot(bot) && on?(room_id)
          say "I'm alive and well :)"
        end
      end
      command "!!/help" do |bot|
        say File.read("./help.txt") if matches_bot(bot) && on?(room_id)
      end
    end
  end

  room HQ_ROOM_ID do
    command("!!/whoami") { say (rand(0...20) == rand(0...20) ? "24601" : "I go by #{BOT_NAMES.join(" and ")}") }
    command("!!/alive") { |bot| say "I'm alive!" if matches_bot(bot) }
    command("!!/help") { |bot| say(File.read('./hq_help.txt')) if matches_bot(bot) }
    command("!!/whitelist") do |bot, *uids|
      if matches_bot(bot)
        uids.each do |uid|
          WhitelistedUser.create(user_id: uid)
        end
        say "Whitelisted users #{uids.join(', ')}"
      end
    end
    command("!!/unwhitelist") do |bot, *uids|
      if matches_bot(bot)
        uids.each do |uid|
          WhitelistedUser.where(user_id: uid).destroy_all
        end
        say "Unwhitelisted users #{uids.join(', ')}"
      end
    end
    command("!!/whitelisted") { |bot, *args| say "Current whitelist: #{WhitelistedUser.all.map(&:user_id).join(', ')}" }
    command("!!/quota") { |bot| say "#{cli.quota} requests remaining" if matches_bot(bot) }
    command("!!/uptime") { |bot| say Time.at(Time.now - start).strftime("Up %j Days, %H hours, %M minutes, %S seconds") if matches_bot(bot) }
    command "!!/logsize" do |bot|
      if matches_bot(bot)
        uncompressed = to_sizes(Dir['*.log']+Dir['*.log.1']).map do |sizes|
          "#{sizes[:file]}: #{sizes[:size].round(2)}#{sizes[:ext]}"
        end
        compressed = {}
        to_sizes(Dir['*.log*.gz']).each do |size|
          compressed[size[:file].split('.')[0]] ||= 0
          compressed[size[:file].split('.')[0]] += size[:size]
        end
        say((uncompressed + compressed.map { |b, s| "#{b}: #{s.round(2)}MB" }).join("\n"))
      end
    end
    command("!!/howmany") { |bot| say "I've scanned #{Comment.count} comments" if matches_bot(bot) }
    command "!!/test" do |bot, type, *body|
      if matches_bot(bot)
        say "Unknown post type '#{type}'" unless %w[q a].include? type[0]
        say(report(type, body.join(" ")) || "Didn't match any filters")
      end
    end
    command "!!/howgood" do |bot, type, regex|
      if matches_bot(bot)
        type = 'question' if type == 'q'
        type = 'answer' if type == 'a'
        if %w[question answer *].include? type
          if type == '*'
            tps = Comment.where("tps >= ?", 1).count { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }.to_f
            fps = Comment.where("fps >= ?", 1).count { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }.to_f
            total = Comment.count { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }.to_f
          else
            tps = Comment.where(post_type: type).where("tps >= ?", 1).count { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }.to_f
            fps = Comment.where(post_type: type).where("fps >= ?", 1).count { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }.to_f
            total = Comment.where(post_type: type).count { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }.to_f
          end
          
          tp_msg = [ #Generate tp line
            'tp'.center(6),
            tps.round(0).to_s.center(11),
            percent_str(tps, total).center(14),
            percent_str(tps, Comment.where("tps >= ?", 1).count).center(15),
            percent_str(tps, Comment.count).center(18),
          ].join('|')

          fp_msg = [ #Generate fp line
            'fp'.center(6),
            fps.round(0).to_s.center(11),
            percent_str(fps, total).center(14),
            percent_str(fps, Comment.where("fps >= ?", 1).count).center(15),
            percent_str(fps, Comment.count).center(18),
          ].join('|')

          total_msg = [ #Generate total line
            'Total'.center(6),
            total.round(0).to_s.center(11),
            '-'.center(14),
            '-'.center(15),
            percent_str(total, Comment.count).center(18),
          ].join('|')

          #Generate header line
          header = " Type | # Matched | % of Matched | % of All Type | % of ALL Comments"

          final_output = [ #Add 4 spaces for formatting and newlines
            header, '-'*68, tp_msg, fp_msg, total_msg
          ].join("\n    ")
          msgs = MessageCollection::ALL_ROOMS
          msgs.push_howgood [regex, type], (say "    #{final_output}")
        else
          say "Type must be q/a/question/answer/*"
        end
      end
    end
    command "!!/add" do |bot, type, regex, *reason|
      if matches_bot(bot) && r = Reason.find_or_create_by(name: reason.join(' ')).regexes.create(post_type: type[0], regex: regex)
        say "Added regex #{r.regex} for post_type #{r.post_type} with reason '#{r.reason.name}'"
      end
    end
    command "!!/del" do |bot, type, regex|
      if matches_bot(bot)
        if r = Regex.find_by(post_type: type[0], regex: regex)
          say "Destroyed #{r.regex} (post_type #{r.post_type})!" if r.destroy
        else
          say "Could not find regex to destroy"
        end
      end
    end
    command "!!/cid" do |bot, cid|
      if matches_bot(bot)
        c = Comment.find_by(comment_id: cid)
        if c
          report_comments(c, cli: cli, settings: settings, cb: cb, should_post_matches: false)
        else
          say "Could not find comment with id #{cid}"
        end
      end
    end
    command "!!/pull" do |bot, *args|
      if matches_bot(bot)
        `git pull`
        Kernel.exec("bundle exec ruby comment_scan.rb #{args.empty? ? post_on_startup : args[0].to_i}")
      end
    end
    command "!!/restart" do |bot, *args|
      if matches_bot(bot)
        Kernel.exec("bundle exec ruby comment_scan.rb #{args.empty? ? post_on_startup : args[0].to_i}")
      end
    end
    command("!!/kill") { |bot| `kill -9 $(cat bot.pid)` if matches_bot(bot) }
    command("!!/rev") { |bot| say "Currently at rev #{`git rev-parse --short HEAD`.chop} on branch #{`git rev-parse --abbrev-ref HEAD`.chop}" if matches_bot(bot) }
    command "!!/manscan" do |bot, *args|
      if matches_bot(bot)
        c = cli.comments(args)
        if c.empty?
          say "No comments found for id(s) #{args.join(", ")}"
        else
          scan_comments(c, cli: cli, settings: settings, cb: cb)
        end
      end
    end
    command("!!/mode") { |bot| say "I'm in parent mode. I have children in rooms #{ROOMS.map { |rid| "[#{rid}](https://chat.stackexchange.com/rooms/#{rid})"}.join(", ")}" if matches_bot(bot) }
    command("!!/ttscan") { |bot| say "#{sleeptime} seconds remaning until the next scan" if matches_bot(bot) }
    command("!!/regexes") do |bot, reason|
      if matches_bot(bot)
        reasons = (reason.nil? ? Reason.all : Reason.where(name: reason)).map do |r|
          regexes = r.regexes.map { |regex| "- #{regex.post_type}: #{regex.regex}" }
          "#{r.name.gsub(/\(\@(\w*)\)/, '(*\1)')}:\n#{regexes.join("\n")}"
        end
        reasonless_regexes = Regex.where(reason_id: nil).map { |regex| "- #{regex.post_type}: #{regex.regex}" }
        reasons << "Other Regexes:\n#{reasonless_regexes.join("\n")}"
        say reasons.join("\n")
      end
    end
  end
end

comments = cli.comments[0..-1]

@last_creation_date = comments[post_on_startup].json["creation_date"].to_i+1 unless comments[post_on_startup].nil?

@logger = Logger.new('msg.log')
@perspective_log = Logger.new('perspective.log')

def scan_comments(*comments, cli:, settings:, cb:, perspective_log: Logger.new('/dev/null'))
  comments.flatten.each do |comment|

    body = comment.json["body_markdown"]
    toxicity = perspective_scan(body, perspective_key: settings['perspective_key']).to_f

    if dbcomment = record_comment(comment, perspective_score: toxicity)
      # MessageCollection::ALL_ROOMS.swap_key(comment, dbcomment)
      report_comments(dbcomment,cli: cli, settings: settings, cb: cb, should_post_matches: true)
    end

    # if reasons.map(&:name).include?('abusive') || reasons.map(&:name).include?('offensive')
    #   Thread.new do
    #     sleep 60
    #     msgs.each do |msg|
    #       cb.delete(msg.to_i)
    #     end
    #   end
    # end

    # @logger.info "Parsed comment:"
    # @logger.info "(JSON) #{comment.json}"
    # @logger.info "(SE::API::Comment) #{comment.inspect}"
    # @logger.info "Current time: #{Time.new.to_i}"

    #rval = cb.say(comment.link, 63296)
    #cb.delete(rval.to_i)
    #cb.say(msg, 63296)
    
  end
end

def report_comments(*comments, cli:, settings:, cb:, should_post_matches: true)
  comments.flatten.each do |comment|
    
    user =  Array(User.where(id: comment["owner_id"]).as_json)
    user = user.any? ? user[0] : false #if user was deleted, set it to false for easy checking
    
    puts "Grab metadata..."
    
    
    author = user ? user["display_name"] : "(removed)"
    author_link = user ? "[#{author}](#{user["link"]})" : "(removed)"
    rep = user ? "#{user["reputation"]} rep" : "(removed) rep"
    
    date = Time.at(comment["creation_date"].to_i)
    seconds = (Time.new - date).to_i
    ts = seconds < 60 ? "#{seconds} seconds ago" : "#{seconds/60} minutes ago"
    
    puts "Grab post data/build message to post..."
    
    msg = "##{comment["post_id"]} #{author_link}"

    puts "Analyzing post..."
    
    post_inactive = false #Default to false in case we can't access post
    post = [] #so that we can use this later for whitelisted users
    
    if !isPostDeleted(cli, comment["post_id"]) #If post wasn't deleted, do full print
      post = Array(cli.posts(comment["post_id"].to_i))[0]
      author = user_for post.owner
      editor = user_for post.last_editor
      creation_ts = ts_for post.json["creation_date"]
      edit_ts = ts_for post.json["last_edit_date"]
      type = post.type[0].upcase
      closed = post.json["close_date"]
      
      post_inactive = Time.at(post.json["last_activity_date"].to_i).to_date < Time.at(comment["creation_date"].to_i).to_date - 30
      
      msg += " | [#{type}: #{post.title}](#{post.link}) #{'[c]' if closed} (score: #{post.score}) | posted #{creation_ts} by #{author}"
      msg += " | edited #{edit_ts} by #{editor}" unless edit_ts.empty? || editor.empty?
    end
    
    #toxicity = perspective_scan(body, perspective_key: settings['perspective_key']).to_f
    toxicity = comment["perspective_score"]
    
    puts "Building message..."
    msg += " | Toxicity #{toxicity}"
    #msg += " | Has magic comment" if !isPostDeleted(cli, comment["post_id"]) and has_magic_comment? comment, post
    msg += " | High toxicity" if toxicity >= 0.7
    msg += " | Comment on inactive post" if post_inactive
    msg += " | tps/fps: #{comment["tps"].to_i}/#{comment["fps"].to_i}"
    
    puts "Building comment body..."
    
    #If the comment exists, we can just post the link and ChatX will do the rest
    #Else, make a quote manually with just the body (no need to be fancy, this must be old)
    #(include a newline in the manual string to lift 500 character limit in chat)
    #TODO: Chat API is truncating to 500 characters right now even though we're good to post more. Fix this.
    comment_text_to_post = isCommentDeleted(cli, comment["comment_id"]) ? ("\n> " + comment["body"]) : comment["link"]
    
    puts "Check reasons..."

    report_text = report(comment["post_type"], comment["body_markdown"])
    reasons = report_raw(comment["post_type"], comment["body_markdown"]).map(&:reason)
    
    if reasons.map(&:name).include?('abusive') || reasons.map(&:name).include?('offensive')
      comment_text_to_post = "⚠️☢️\u{1F6A8} [Offensive/Abusive Comment](#{comment["link"]}) \u{1F6A8}☢️⚠️"
    end
    
    msgs = MessageCollection::ALL_ROOMS

    puts "Post chat message..."

    if settings['all_comments']
      msgs.push comment, cb.say(comment_text_to_post, HQ_ROOM_ID)
      msgs.push comment, cb.say(msg, HQ_ROOM_ID)
      msgs.push comment, cb.say(report_text, HQ_ROOM_ID) if report_text
      # To be totally honest, maintaining this is not worth it to me right now, so I'm gonna stop working on this setting
    #elsif !settings['all_comments'] && (has_magic_comment?(comment, post) || report_text) && !IGNORE_USER_IDS.map(&:to_i).push(post.owner.id).flatten.include?(comment.owner.id.to_i)
    elsif !settings['all_comments'] && (report_text) && (!isPostDeleted(cli, comment["post_id"]) && !IGNORE_USER_IDS.map(&:to_i).push(post.owner.id).flatten.include?(comment.owner.id.to_i))
      msgs.push comment, cb.say(comment_text_to_post, HQ_ROOM_ID)
      msgs.push comment, cb.say(msg, HQ_ROOM_ID)
      msgs.push comment, cb.say(report_text, HQ_ROOM_ID) if report_text
    end
    
    ROOMS.each do |room_id|
      room = Room.find_by(room_id: room_id)
      #puts Array(room.as_json).to_s
      if room.on
        should_post_message = (
                                #(room.magic_comment && has_magic_comment?(comment, post)) ||
                                (room.regex_match && report_text) ||
                                toxicity >= 0.7 || # I should add a room property for this
                                post_inactive # And this
                              ) && should_post_matches && user &&
                              !isPostDeleted(cli, comment["post_id"]) && !IGNORE_USER_IDS.map(&:to_i).push(post.owner.id).map(&:to_i).include?(user["user_id"].to_i) &&
                              (user['user_type'] != 'moderator')
                              
        if should_post_message
          msgs.push comment, cb.say(comment_text_to_post, room_id)
          msgs.push comment, cb.say(msg, room_id)
          msgs.push comment, cb.say(report_text, room_id) if room.regex_match && report_text
        end
      end
    end
  
  end
  
  puts "Processing complete!"

end

sleep 1 # So we don't get chat errors for 3 messages in a row

loop do
  comments = cli.comments(fromdate: @last_creation_date)
  @last_creation_date = comments[0].json["creation_date"].to_i+1 unless comments[0].nil?
  scan_comments(comments, cli: cli, settings: settings, cb: cb)
  sleeptime = 60
  while sleeptime > 0 do sleep 1; sleeptime -= 1 end
end