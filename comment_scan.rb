require "se/api"
require "chatx"
require 'uri'
require 'logger'
require 'time'
require 'yaml'
require './db'

IO.write("bot.pid", Process.pid.to_s)

start = Time.now
manual_scan = []
sleeptime = 0

settings = File.exists?('./settings.yml') ? YAML.load_file('./settings.yml') : ENV

post_on_startup = ARGV[0].to_i || 0

cb = ChatBot.new(settings['ChatXUsername'], settings['ChatXPassword'])
cli = SE::API::Client.new(settings['APIKey'], site: settings['site'])
HQ_ROOM_ID = settings['hq_room_id'].to_i
ROOMS = settings['rooms']
cb.login
cb.say("_Starting at rev #{`git rev-parse --short HEAD`.chop} on branch #{`git rev-parse --abbrev-ref HEAD`.chop} (#{`git log -1 --pretty=%B`.gsub("\n", '')})_", HQ_ROOM_ID)
cb.join_room HQ_ROOM_ID
cb.join_rooms ROOMS
BOT_NAME = settings['name']
def matches_bot(bot)
  puts "Checking if #{bot} matches #{BOT_NAME}"
  bot.nil? || bot == '*' || bot.downcase == BOT_NAME
end

ROOMS.each do |room_id|
  Room.find_or_create_by(room_id: room_id)
end

def on?(room_id)
  Room.find_by(room_id: room_id).on
end

cb.gen_hooks do
  ROOMS.each do |room_id|
    room room_id do
      command "!!/off" do |bot|
        if matches_bot(bot) && on?(room_id)
          say "Turning off..."
          Room.find_by(room_id: room_id).update(on: false)
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
                  "magic" => :magic_match
                }[type]
          status = {"on" => true, "off" => false}[status]
          Room.find_by(room_id: room_id).update(**{act => status}) unless status.nil? || act.nil?
        end
      end
      command "!!/alive" do |bot|
        if matches_bot(bot) && on?(room_id)
          say "I'm alive and well :)"
        end
      end
    end
  end

  room HQ_ROOM_ID do
    command("!!/whoami") { |bot| say (rand(0...20) == rand(0...20) ? "24601" : BOT_NAME) }
    command("!!/alive") { |bot| say "I'm alive!" if matches_bot(bot) }
    command("!!/help") { |bot| say(File.read('./help.txt')) if matches_bot(bot) }
    command("!!/quota") { |bot| say "#{cli.quota} requests remaining" if matches_bot(bot) }
    command("!!/uptime") { |bot| say Time.at(Time.now - start).strftime("Up %H hours, %M minutes, %S seconds") if matches_bot(bot) }
    # command "!!/logsize" do
    #   say(%w[api_json.log api_raw.log msg.log websocket_raw.log websockets_json.log].map do |log|
    #     log_file = "./#{log}"
    #     "#{log}: #{(File.size(log_file).to_f/(1024**2)).round(2)}MB" if File.exist? log_file
    #   end.join("\n"))
    # end
    command("!!/howmany") { |bot| say "I've scanned #{Comment.count} comments" if matches_bot(bot) }
    command "!!/test" do |bot, type, *body|
      if matches_bot(bot)
        say "Unknown post type '#{type}'" unless %w[q a].include? type[0]
        say(report(type, body.join(" ")) || "Didn't match any filters")
      end
    end
    command "!!/add" do |bot, type, regex, *reason|
      if matches_bot(bot) && r = Reason.find_or_create_by(name: reason.join(' ')).regexes.create(post_type: type[0], regex: regex)
        say "Added regex #{r.regex} for post_type #{r.post_type} with reason '#{r.reason.name}'"
      end
    end
    command "!!/del" do |bot, type, regex, *reason|
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
    command "!!/manscan" do |*args|
      manual_scan += cli.comments(args)
    end
    command("!!/ttscan") { |bot| say "#{sleeptime} seconds remaning until the next scan" if matches_bot(bot) }
  end
end

comments = cli.comments[0..-1]

@last_creation_date = comments[post_on_startup].json["creation_date"].to_i+1 unless comments[post_on_startup].nil?

@logger = Logger.new('msg.log')

def ts_for(ts)
  return "" if ts.nil?
  ts = (Time.new - Time.at(ts.to_i)).to_i
  return "" if ts < 0
  if ts < 60
    "#{ts} seconds ago"
  elsif ts/60 < 60
    "#{ts/60} minutes ago"
  elsif ts/(60**2) < 60
    "#{ts/(60**2)} hours ago"
  else
    "#{ts/(24*60*60)} days ago"
  end
end

def user_for(author)
  return "" unless author.is_a? SE::API::User
  name = author.name
  link = author.link&.gsub(/(^.*u[sers]{4}?\/\d*)\/.*$/, '\1')&.gsub("/users/", "/u/")
  rep = author.reputation
  return "(deleted user)" if name.nil? && link.nil? && rep.nil?
  "[#{name}](#{link}) (#{rep} rep)"
end

def record_comment(comment)
  return false unless comment.is_a? SE::API::Comment
  c = Comment.new
  %i[body body_markdown comment_id creation_date edited link post_id post_type score].each do |f|
    c.send(:"#{f}=", comment.send(f))
  end
  c.save unless Comment.exists?(c.attributes.reject { |_k,v| v.nil? })
end

def report(post_type, comment)
  regexes = Regex.where(post_type: post_type[0].downcase)
  matching_regexes = regexes.select do |regex|
    %r{#{regex.regex}}.match? comment.downcase
  end
  return "Matched regex(es) #{matching_regexes.map { |r| r.reason.nil? ? r.regex : r.reason.name }.uniq }" unless matching_regexes.empty?
end

def has_magic_comment?(comment, post)
  !comment.body_markdown.include?("https://interpersonal.meta.stackexchange.com/q/1644/31") &&
  post.comments.any? do |c|
    c.body_markdown.include?("https://interpersonal.meta.stackexchange.com/q/1644/31")
  end
end

sleep 1 # So we don't get chat errors for 3 messages in a row

loop do
  comments = cli.comments(fromdate: @last_creation_date) + manual_scan
  manual_scan = []
  @last_creation_date = comments[0].json["creation_date"].to_i+1 unless comments[0].nil?
  puts comments.length
  comments.each do |comment|
    author = comment.owner
    base = "https://#{URI(author.link).host}"

    author_link = "[#{author.name}](#{base}/u/#{author.id})"

    body = comment.json["body_markdown"]

    rep = "#{author.reputation} rep"

    max_len = 200

    date = Time.at(comment.json["creation_date"].to_i)
    seconds = (Time.new - date).to_i
    ts = seconds < 60 ? "#{seconds} seconds ago" : "#{seconds/60} minutes ago"

    post = cli.posts(comment.json["post_id"])[0]

    author = user_for post.owner
    editor = user_for post.last_editor
    creation_ts = ts_for post.json["creation_date"]
    edit_ts = ts_for post.json["last_edit_date"]
    type = post.type[0].upcase
    cb.say(comment.link, HQ_ROOM_ID)
    msg = "##{post.json["post_id"]} #{user_for(comment.owner)} | [#{type}: #{post.title}](#{post.link}) (score: #{post.score}) | posted #{creation_ts} by #{author}"
    msg += " | edited #{edit_ts} by #{editor}" unless edit_ts.empty? || editor.empty?
    # msg += " | @Mithrandir (has magic comment)" if !(comment.body_markdown.include?("https://interpersonal.meta.stackexchange.com/q/1644/31") && comment.owner.id == 31) && post.comments.any? { |c| c.body_markdown.include?("https://interpersonal.meta.stackexchange.com/q/1644/31") && c.user.id.to_i == 31 }
    msg += " | @Mithrandir (has magic comment)" if has_magic_comment? comment, post
    cb.say(msg, HQ_ROOM_ID)

    report_text = report(post.type, comment.body_markdown)
    cb.say(report_text, HQ_ROOM_ID) if report_text

    ROOMS.each do |room_id|
      room = Room.find_by(room_id: room_id)
      if room.on
        if room.on && ((room.magic_match && has_magic_comment?(comment, post)) || (room.regex_match && report_text))
          cb.say(msg, room_id)
          cb.say(report_text, room_id) if room.regex_match && report_text
        end 
      end
    end
    @logger.info "Parsed comment:"
    @logger.info "(JSON) #{comment.json}"
    @logger.info "(SE::API::Comment) #{comment.inspect}"
    @logger.info "Current time: #{Time.new.to_i}"

    #rval = cb.say(comment.link, 63296)
    #cb.delete(rval.to_i)
    #cb.say(msg, 63296)

    record_comment(comment)    
  end
  sleeptime = 60
  while sleeptime > 0 do sleep 1; sleeptime -= 1 end
end
