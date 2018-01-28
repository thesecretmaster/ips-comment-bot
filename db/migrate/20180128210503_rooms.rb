class Rooms < ActiveRecord::Migration[5.1]
  def change
    create_table :rooms do |i|
      i.integer :room_id
      i.boolean :magic_comment
      i.boolean :regex_match
      i.boolean :on
    end
  end
end
