require "se/api"
require "chatx"
require 'uri'
require 'logger'
require 'time'
require 'yaml'
require './db'
require 'pry-byebug'

require_relative 'comment_scan/helpers'

IO.write("bot.pid", Process.pid.to_s)

start = Time.now
manual_scan = []
sleeptime = 0

$message_tracker = []
=begin
[
[[messages, which, are, for, this, comment, db, id], Comment]
]
=end

$debug_log = Logger.new('ips_debug.log')

settings = File.exists?('./settings.yml') ? YAML.load_file('./settings.yml') : ENV

post_on_startup = ARGV[0].to_i || 0

cb = ChatBot.new(settings['ChatXUsername'], settings['ChatXPassword'])
cli = SE::API::Client.new(settings['APIKey'], site: settings['site'])
HQ_ROOM_ID = settings['hq_room_id'].to_i
ROOMS = settings['rooms']
IGNORE_USER_IDS = Array(settings['ignore_user_ids'])
cb.login
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
        comment = $message_tracker.select { |msg_ids, comment| msg_ids.include?(msg.hash['parent_id'].to_i) }
        $debug_log.info comment
        comment = comment[0]
        $debug_log.info comment
        comment = comment[1]
        $debug_log.info comment
        if comment.is_a? Comment
          case msg.body.split(' ')[1][0..2].downcase
          when 'tp'
            comment.tps ||= 0
            comment.tps += 1
            cb.say "Regestered as a tp", room_id
          when 'fp'
            comment.fps ||= 0
            comment.fps += 1
            cb.say "Regesterd as a fp", room_id
          when 'wrongo'
            comment.fps ||= 0
            comment.fps += 1
            cb.say "Registered as WRONGO", room_id
          when 'rude'
            comment.rude ||= 0
            comment.rude += 1
            cb.say "Regiestered as rude", room_id
          end
          comment.save
        else
          cb.say "An error has occured", room_id
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
        if type == 'question' || type == 'answer'
          num = Comment.where(post_type: type).count { |comment| %r{#{regex}}.match(comment.body_markdown) }.to_f
          say "Matched #{num} comments (#{(num/Comment.count).round(2)}%)"
        else
          say "Type must be q/a/question/answer"
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
          say c.body_markdown
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
          "#{r.name}:\n#{regexes.join("\n")}"
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

    puts "Grab metadata..."

    author = comment.owner
    base = "https://#{URI(author.link).host}"

    author_link = "[#{author.name}](#{base}/u/#{author.id})"

    body = comment.json["body_markdown"]

    rep = "#{author.reputation} rep"

    max_len = 200

    date = Time.at(comment.json["creation_date"].to_i)
    seconds = (Time.new - date).to_i
    ts = seconds < 60 ? "#{seconds} seconds ago" : "#{seconds/60} minutes ago"

    puts "Grab post data..."

    post = cli.posts(comment.json["post_id"])[0]

    author = user_for post.owner
    editor = user_for post.last_editor
    creation_ts = ts_for post.json["creation_date"]
    edit_ts = ts_for post.json["last_edit_date"]
    type = post.type[0].upcase

    closed = post.json["close_date"]

    toxicity = perspective_scan(body, perspective_key: settings['perspective_key'])

    puts "Compile message..."

    msg = "##{post.json["post_id"]} #{user_for(comment.owner)} | [#{type}: #{post.title}](#{post.link}) #{'[c]' if closed} (score: #{post.score}) | posted #{creation_ts} by #{author} | Toxicity #{toxicity}"
    msg += " | edited #{edit_ts} by #{editor}" unless edit_ts.empty? || editor.empty?
    # msg += " | @Mithrandir (has magic comment)" if !(comment.body_markdown.include?("https://interpersonal.meta.stackexchange.com/q/1644/31") && comment.owner.id == 31) && post.comments.any? { |c| c.body_markdown.include?("https://interpersonal.meta.stackexchange.com/q/1644/31") && c.user.id.to_i == 31 }
    msg += " | Has magic comment" if has_magic_comment? comment, post

    puts "Check reasons..."

    report_text = report(post.type, comment.body_markdown)
    reasons = report_raw(post.type, comment.body_markdown).map(&:reason)
    comment_link = comment.link
    if reasons.map(&:name).include?('abusive') || reasons.map(&:name).include?('offensive')
      comment_link = "⚠️☢️\u{1F6A8} [Offensive/Abusive Comment](#{comment_link}) \u{1F6A8}☢️⚠️"
    end

    msgs = []

    puts "Post chat message..."

    if settings['all_comments']
      msgs.push cb.say(comment.link, HQ_ROOM_ID)
      msgs.push cb.say(msg, HQ_ROOM_ID)
      msgs.push cb.say(report_text, HQ_ROOM_ID) if report_text
    elsif !settings['all_comments'] && (has_magic_comment?(comment, post) || report_text) && !IGNORE_USER_IDS.map(&:to_i).include?(comment.owner.id.to_i)
      msgs.push cb.say(comment.link, HQ_ROOM_ID)
      msgs.push cb.say(msg, HQ_ROOM_ID)
      msgs.push cb.say(report_text, HQ_ROOM_ID) if report_text
    end

    ROOMS.each do |room_id|
      room = Room.find_by(room_id: room_id)
      if room.on
        if ((room.magic_comment && has_magic_comment?(comment, post)) || (room.regex_match && report_text)) && !IGNORE_USER_IDS.map(&:to_i).include?(comment.owner.id.to_i) && comment.owner.json['user_type'] != 'moderator'
          msgs.push cb.say(comment_link, room_id)
          msgs.push cb.say(msg, room_id)
          msgs.push cb.say(report_text, room_id) if room.regex_match && report_text
        end
      end
    end

    puts "Log to database..."

    $message_tracker.push([msgs, record_comment(comment)])
    $message_tracker.pop if $message_tracker.length > 30

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

    puts "Processing complete!"
  end
end

sleep 1 # So we don't get chat errors for 3 messages in a row

loop do
  comments = cli.comments(fromdate: @last_creation_date) + manual_scan
  manual_scan = []
  @last_creation_date = comments[0].json["creation_date"].to_i+1 unless comments[0].nil?
  scan_comments(comments, cli: cli, settings: settings, cb: cb)
  sleeptime = 60
  while sleeptime > 0 do sleep 1; sleeptime -= 1 end
end
