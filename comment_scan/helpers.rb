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
  #return "" unless author.is_a? SE::API::User
  name = author.name
  link = author.link&.gsub(/(^.*u[sers]{4}?\/\d*)\/.*$/, '\1')&.gsub("/users/", "/u/")
  rep = author.reputation
  return "(deleted user)" if name.nil? && link.nil? && rep.nil?
  "[#{name}](#{link}) (#{rep} rep)"
end

def report_raw(post_type, comment_body)
  regexes = Regex.where(post_type: post_type[0].downcase)
  regexes.select do |regex|
    %r{#{regex.regex}}.match? comment_body.downcase
  end
end

def report(post_type, comment_body)
  matching_regexes = report_raw(post_type, comment_body)
  return "Matched regex(es) #{matching_regexes.map { |r| r.reason.nil? ? r.regex : r.reason.name }.uniq }" unless matching_regexes.empty?
end

def has_magic_comment?(comment, post)
  !comment.body_markdown.include?("https://interpersonal.meta.stackexchange.com/q/1644/31") &&
  post.comments.any? do |c|
    c.body_markdown.include?("https://interpersonal.meta.stackexchange.com/q/1644/31")
  end
end

def percent_str(numerator, denominator, precision: 8, blank_str: '-')
  return blank_str if denominator.zero?
  "#{(numerator*100.0/denominator).round(precision)}%"
end

def timestamp_to_date(timestamp)
  Time.at(timestamp.to_i).to_date
end

def random_response()
  responses = ["Ain't that the truth.",
               "You're telling me.",
               "Yep. That's about the size of it.",
               "That's what I've been saying for $(AGE_OF_BOT)!",
               "What else is new?",
               "For real?",
               "Humans, amirite?"]

  return responses[rand(responses.length())]
end
