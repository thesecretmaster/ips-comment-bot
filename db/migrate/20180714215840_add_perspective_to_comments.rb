class AddPerspectiveToComments < ActiveRecord::Migration[5.2]
  def change
    add_column :comments, :perspective_score, :decimal, precision: 15, scale: 10
  end
end
