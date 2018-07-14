class FixColName < ActiveRecord::Migration[5.2]
  def change
    rename_column :users, :type, :user_type
    rename_column :comments, :owner, :owner_id
  end
end
