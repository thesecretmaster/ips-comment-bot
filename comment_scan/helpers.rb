require_relative '../db.rb'
require 'httparty'
require 'htmlentities'

def on?(room_id)
  Room.find_by(room_id: room_id).on
end

def to_sizes(filenames)
  filenames.map do |filename|
    full_name = "./#{filename}"
    fsize, ext = File.size(full_name).to_f/(1024**2), "MB"
    {
      file: filename,
      size: fsize,
      ext: ext
    }
  end
end

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

def record_comment(comment, perspective_score:)
  return false unless comment.is_a? SE::API::Comment
  c = Comment.new
  %i[body body_markdown comment_id edited link post_id post_type score].each do |f|
    value = comment.send(f)
    value = HTMLEntities.new.decode(value) if %i[body body_markdown].include? f
    c.send(:"#{f}=", value)
  end
  c.perspective_score = perspective_score
  c.se_creation_date = comment.creation_date
  if Comment.exists?(c.attributes.reject { |_k,v| v.nil? })
    Comment.find_by(c.attributes.reject { |_k,v| v.nil? })
  else
    api_u = comment.owner
    u = User.find_or_create_by(user_id: api_u.id)
    u.update(display_name: api_u.name, reputation: api_u.reputation, link: api_u.link, user_type: api_u.type)
    c.owner = u
    puts u.inspect
    puts c.inspect
    if c.save
      c
    else
      puts c.errors.full_messages
    end
  end
end

def report_raw(post_type, comment)
  regexes = Regex.where(post_type: post_type[0].downcase)
  regexes.select do |regex|
    %r{#{regex.regex}}.match? comment.downcase
  end
end

def report(post_type, comment)
  matching_regexes = report_raw(post_type, comment)
  return "Matched regex(es) #{matching_regexes.map { |r| r.reason.nil? ? r.regex : r.reason.name }.uniq }" unless matching_regexes.empty?
end

def has_magic_comment?(comment, post)
  !comment.body_markdown.include?("https://interpersonal.meta.stackexchange.com/q/1644/31") &&
  post.comments.any? do |c|
    c.body_markdown.include?("https://interpersonal.meta.stackexchange.com/q/1644/31")
  end
end

def perspective_scan(text, perspective_key: '', perspective_log: Logger.new('/dev/null'))
  if perspective_key
    puts "Perspective scan..."
    response = HTTParty.post("https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze?key=#{perspective_key}",
    :body => {
        "comment" => {
          text: text,
          type: 'PLAIN_TEXT' # This should eventually be HTML, when perspective supports it
        },
        "context" => {}, # Not yet supported
        "requestedAttributes" => {
          'TOXICITY' => {
            scoreType: 'PROBABILITY',
            scoreThreshold: 0
          }
        },
        "languages" => ["en"],
        "doNotStore" => true,
        "sessionId" => '' # Use this if there are multiple bots running
      }.to_json,
    :headers => { 'Content-Type' => 'application/json' } )

    perspective_log.info response
    perspective_log.info response.dig("attributeScores")
    perspective_log.info response.dig("attributeScores", "TOXICITY")
    perspective_log.info response.dig("attributeScores", "TOXICITY", "summaryScore")
    perspective_log.info response.dig("attributeScores", "TOXICITY", "summaryScore", "value")
    response.dig("attributeScores", "TOXICITY", "summaryScore", "value")
  else
    'NoKey'
  end
end

def percent_str(numerator, denominator)
  return '-' if denominator.zero?
  "#{(numerator*100.0/denominator).round(8)}%"
end
