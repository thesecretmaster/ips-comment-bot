class AddNoticeTable < ActiveRecord::Migration[5.2]
  def change
    create_table :noticed_users do |i|
      i.bigint :user_id
    end
  end
end
