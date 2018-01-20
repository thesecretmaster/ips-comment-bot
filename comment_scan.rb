require "se/api"
require "chatx"
require 'uri'
require 'logger'
require 'time'
require 'yaml'
require './db'

$start = Time.now

settings = File.exists?('./settings.yml') ? YAML.load_file('./settings.yml') : ENV

cb = ChatBot.new(settings['ChatXUsername'], settings['ChatXPassword'])
cli = SE::API::Client.new(settings['APIKey'], site: 'interpersonal')

cb.login

cb.join_room 63296

cb.gen_hooks do
  room 63296 do
    command("!!/alive") { say "I'm alive!" }
    command("!!/help") { say(File.read('./help.txt')) }
    command("!!/quota") { say "#{cli.quota} requests remaining" }
    command("!!/uptime") { say Time.at(Time.now - $start).strftime("Up %H hours, %M minutes, %S seconds") }
    command "!!/logsize" do
      say(%w[api_json.log api_raw.log msg.log websocket_raw.log websockets_json.log].map do |log|
        log_file = "./#{log}"
        "#{log}: #{(File.size(log_file).to_f/(1024**2)).round(2)}MB" if File.exist? log_file
      end.join("\n"))
    end
    command("!!/howmany") { say "I've scanned #{Comment.count} comments" }
  end
end

comments = cli.comments[0..-1]

post_on_startup = 1

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
  link = author.link.gsub("/users/", "/u/")
  rep = author.reputation
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

loop do
  comments = cli.comments(fromdate: @last_creation_date)
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
    cb.say(msg, 63296)

    @logger.info "Parsed comment:"
    @logger.info "(JSON) #{comment.json}"
    @logger.info "(SE::API::Comment) #{comment.inspect}"
    @logger.info "Current time: #{Time.new.to_i}"
    #rval = cb.say(comment.link, 63296)
    #cb.delete(rval.to_i)
    #cb.say(msg, 63296)

    record_comment(comment)    
  end
  sleep 60
end
