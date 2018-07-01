class AddWhitelistTable < ActiveRecord::Migration[5.2]
  def change
    create_table :whitelisted_users do |i|
      i.bigint :user_id
    end
  end
end
