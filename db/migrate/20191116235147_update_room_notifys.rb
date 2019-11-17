class UpdateRoomNotifys < ActiveRecord::Migration[5.2]
  def change
    add_column :rooms, :hot_post, :boolean
    add_column :rooms, :inactive_post, :boolean
    add_column :rooms, :custom_report, :boolean
    add_column :rooms, :animals, :boolean
    remove_column :rooms, :magic_comment
  end
end
