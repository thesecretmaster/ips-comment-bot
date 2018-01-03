require "se/api"
require "chatx"
require 'uri'
require 'logger'
require 'time'

$start = Time.now

cb = ChatBot.new(ENV['ChatXUsername'], ENV['ChatXPassword'])
cli = SE::API::Client.new(ENV['APIKey'], site: 'interpersonal')

cb.login

cb.join_room 63296

cb.gen_hooks do
  room 63296 do
    command("!!/alive") { say "I'm alive!" }
    command("!!/quota") { say "#{cli.quota} requests remaining" }
    command("!!/uptime") { say Time.at(Time.now - $start).strftime("Up %H hours, %M minutes, %S seconds") }
  end
end

comments = cli.comments[0..-1]

post_on_startup = 0

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
  return "" if author.to_s.empty?
  name = author["display_name"]
  link = author["link"]
  rep = author["reputation"]
  "[#{name}](#{link}) (#{rep} rep)"
end

loop do
  comments = cli.comments(fromdate: @last_creation_date)
  @last_creation_date = comments[0].json["creation_date"].to_i+1 unless comments[0].nil?
  puts comments.length
  comments.each do |comment|
    author = comment.json["owner"]
    base = "https://#{URI(author["link"]).host}"

    author_link = "[#{author["display_name"]}](#{base}/u/#{author["user_id"]})"

    body = comment.json["body_markdown"]

    rep = "#{author["reputation"]} rep"

    max_len = 200

    date = Time.at(comment.json["creation_date"].to_i)
    seconds = (Time.new - date).to_i
    ts = seconds < 60 ? "#{seconds} seconds ago" : "#{seconds/60} minutes ago"

    comment_metadata = "#{author_link} (#{rep}) [#{ts}](#{base}/posts/comments/#{comment.id})"
    comment_md = "#{body[0..max_len]}#{'...' if body.length > max_len} — #{comment_metadata}"

    post = cli.posts(comment.json["post_id"])[0]
    post_md = "[#{post.title}](#{post.link}) (#{post.score})"

    msg = "> #{comment_md} | #{post_md}"

    author = user_for post.json["owner"]
    editor = user_for post.json["last_editor"]
    creation_ts = ts_for post.json["creation_date"]
    edit_ts = ts_for post.json["last_edit_date"]
    type = post.json["post_type"][0].upcase
    cb.say(comment.link, 63296)
    msg = "##{post.json["post_id"]} [#{type}: #{post.title}](#{post.link}) (score: #{post.score}) | posted #{creation_ts} by #{author}"
    msg += " | edited #{edit_ts} by #{editor}" unless edit_ts.empty? || editor.empty?
    cb.say(msg, 63296)

    @logger.info "Parsed comment:"
    @logger.info "(JSON) #{comment.json}"
    @logger.info "(SE::API::Comment) #{comment.inspect}"
    @logger.info "Current time: #{Time.new.to_i}"
    #rval = cb.say(comment.link, 63296)
    #cb.delete(rval.to_i)
    #cb.say(msg, 63296)
  end
  sleep 60
end
