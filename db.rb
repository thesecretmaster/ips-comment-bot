require "active_record"
require "htmlentities"

def setup_db(db_location)
  ActiveRecord::Base.establish_connection(
    adapter: "sqlite3",
    database: db_location
  )
end

def wipe_db
  User.delete_all
  Comment.delete_all
  Regex.delete_all
  Reason.delete_all
  Room.delete_all
  WhitelistedUser.delete_all
end


class User < ActiveRecord::Base
  has_many :comments, foreign_key: 'owner'
end

class Comment < ActiveRecord::Base
  belongs_to :owner, class_name: "User"
  # has_one :user, as: :reply_to_user
  before_save :update_creation_date

  def update_creation_date
    self.creation_date = Time.at(self.se_creation_date.to_i).to_datetime
  end

  def self.record_comment(comment, logger, perspective_score:)
    #return false unless comment.is_a? SE::API::Comment
    c = Comment.new
    %i[body body_markdown comment_id edited link post_id post_type score].each do |f|
      value = comment.send(f)
      value = HTMLEntities.new.decode(value) if %i[body body_markdown].include? f
      c.send(:"#{f}=", value)
    end
    c.perspective_score = perspective_score
    c.se_creation_date = comment.creation_date
    #TODO: This looks like a bug...it'll think that any comment with tps/fps marked doesn't exist (so I believe)
    # couldn't we just do a lookup by id??
    if Comment.exists?(c.attributes.reject { |_k,v| v.nil? })
      Comment.find_by(c.attributes.reject { |_k,v| v.nil? })
    else
      api_u = comment.owner
      u = User.find_or_create_by(user_id: api_u.id)
      u.update(display_name: api_u.name, reputation: api_u.reputation, link: api_u.link, user_type: api_u.type)
      c.owner = u
      logger.debug u.inspect
      logger.debug c.inspect
      if c.save
        c
      else
        logger.error c.errors.full_messages
      end
    end
  end
end

class Regex < ActiveRecord::Base
  belongs_to :reason
end

class Reason < ActiveRecord::Base
  has_many :regexes
end

class Room < ActiveRecord::Base
  def on?
    self.on
  end

  def turn_on
    self.on = true
  end

  def turn_off
    self.on = false
  end
end

class WhitelistedUser < ActiveRecord::Base
end
