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
cli = SE::API::Client.new(settings['APIKey'], site: 'interpersonal')

cb.login
cb.say("_Starting at rev #{`git rev-parse --short HEAD`.chop} on branch #{`git rev-parse --abbrev-ref HEAD`.chop} (#{`git log -1 --pretty=%B`.gsub("\n", '')})_", 63296)
cb.join_room 63296

cb.gen_hooks do
  room 63296 do
    command("!!/alive") { say "I'm alive!" }
    command("!!/help") { say(File.read('./help.txt')) }
    command("!!/quota") { say "#{cli.quota} requests remaining" }
    command("!!/uptime") { say Time.at(Time.now - start).strftime("Up %H hours, %M minutes, %S seconds") }
    command "!!/logsize" do
      say(%w[api_json.log api_raw.log msg.log websocket_raw.log websockets_json.log].map do |log|
        log_file = "./#{log}"
        "#{log}: #{(File.size(log_file).to_f/(1024**2)).round(2)}MB" if File.exist? log_file
      end.join("\n"))
    end
    command("!!/howmany") { say "I've scanned #{Comment.count} comments" }
    command "!!/test" do |type, *body|
      say(report(type, body.join(" ")) || "Didn't match any filters")
    end
    command "!!/add" do |type, *regex|
      if r = Regex.create(post_type: type[0], regex: regex.join(" "))
        say "Added regex #{r.regex} for post_type #{r.post_type}"
      end
    end
    command "!!/del" do |type, *regex|
      if r = Regex.find_by(post_type: type[0], regex: regex.join(' '))
        say "Destroyed #{r.regex} (post_type #{r.post_type})!" if r.destroy
      else
        say "Could not find regex to destroy"
      end
    end
    command "!!/cid" do |cid|
      c = Comment.find_by(comment_id: cid)
      say c.body_markdown if c
    end
    command "!!/pull" do |*args|
      `git pull`
      Kernel.exec("bundle exec ruby comment_scan.rb #{args.empty? ? post_on_startup : args.join(' ')}")
    end
    command "!!/restart" do |*args|
      Kernel.exec("bundle exec ruby comment_scan.rb #{args.empty? ? post_on_startup : args.join(' ')}")
    end
    command("!!/kill") { `kill -9 $(cat bot.pid)` }
    command("!!/rev") { say "Currently at rev #{`git rev-parse --short HEAD`.chop} on branch #{`git rev-parse --abbrev-ref HEAD`.chop}" }
    command "!!/manscan" do |*args|
      manual_scan += cli.comments(args)
    end
    command("!!/ttscan") { say "#{sleeptime} seconds remaning until the next scan" }
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
  return "(deleted user #{author.id})" if name.nil? && link.nil? && rep.nil?
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
  case post_type[0].downcase
  when "q"
    regexes = Regex.where(post_type: 'q').map { |r| %r{#{r.regex}} }
    matching_regexes = regexes.select do |regex|
      regex.match? comment.downcase
    end
    return "Matched regex(es) #{matching_regexes}" unless matching_regexes.empty?
  when "a"
    regexes = Regex.where(post_type: 'a').map { |r| %r{#{r.regex}} }
    matching_regexes = regexes.select do |regex|
      regex.match? comment.downcase
    end
    return "Matched regex(es) #{matching_regexes}" unless matching_regexes.empty?
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
    cb.say(comment.link, 63296)
    msg = "##{post.json["post_id"]} #{user_for(comment.owner)} | [#{type}: #{post.title}](#{post.link}) (score: #{post.score}) | posted #{creation_ts} by #{author}"
    msg += " | edited #{edit_ts} by #{editor}" unless edit_ts.empty? || editor.empty?
    # .reject { |c| c.owner.id.to_i == 31 }
    msg += " | @Mithrandir (has magic comment)" if post.comments.any? { |c| c.body_markdown.include?("https://interpersonal.meta.stackexchange.com/q/1644/31") && c.user.id.to_i == 31 }
    cb.say(msg, 63296)
    @logger.info "Parsed comment:"
    @logger.info "(JSON) #{comment.json}"
    @logger.info "(SE::API::Comment) #{comment.inspect}"
    @logger.info "Current time: #{Time.new.to_i}"

    report_text = report(post.type, comment.body_markdown)
    cb.say(report_text, 63296) if report_text

    #rval = cb.say(comment.link, 63296)
    #cb.delete(rval.to_i)
    #cb.say(msg, 63296)

    record_comment(comment)    
  end
  sleeptime = 60
  while sleeptime > 0 { sleep 1; sleeptime -= 1 }
end
