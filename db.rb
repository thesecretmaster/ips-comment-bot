require "active_record"

def setup_db(db_location)
  ActiveRecord::Base.establish_connection(
    adapter: "sqlite3",
    database: db_location
    #database: "db/test_db.sqlite3"
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
end

class Regex < ActiveRecord::Base
  belongs_to :reason
end

class Reason < ActiveRecord::Base
  has_many :regexes
end

class Room < ActiveRecord::Base
  def self.on?(room_id)
    find_by(room_id: room_id).on
  end

  def self.turn_on(room_id)
    find_by(room_id: room_id).update(on: true)
  end

  def self.turn_off(room_id)
    find_by(room_id: room_id).update(on: false)
  end
end

class WhitelistedUser < ActiveRecord::Base
end
