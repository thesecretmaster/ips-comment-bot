class AddFeedbacks < ActiveRecord::Migration[5.2]
  def change
    add_column :comments, :tps, :integer
    add_column :comments, :fps, :integer
    add_column :comments, :rude, :integer
  end
end
