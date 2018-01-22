require "active_record"

ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: "db/db.sqlite3"
)

class User < ActiveRecord::Base
end

class Comment < ActiveRecord::Base
  has_one :user, as: :owner
  has_one :user, as: :reply_to_user
end

class Regex < ActiveRecord::Base
  belongs_to :reason
end

class Reason < ActiveRecord::Base
  has_many :regexes
end
