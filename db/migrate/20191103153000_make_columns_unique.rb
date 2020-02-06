class MakeColumnsUnique < ActiveRecord::Migration[6.0]
  def change
    add_index :chat_users, :user_id, unique: true
    add_index :users, :user_id, unique: true
    add_index :whitelisted_users, :user_id, unique: true

    add_column :feedbacks, :room_id, :integer
  end
end
