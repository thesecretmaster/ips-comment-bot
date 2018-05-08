class RealDatetimes < ActiveRecord::Migration[5.2]
  def self.up
    rename_column :comments, :creation_date, :se_creation_date
    add_column :comments, :creation_date, :datetime
    Comment.all.each do |comment|
      comment.update(creation_date: Time.at(comment.se_creation_date.to_i).to_datetime)
    end
  end

  def self.down
    remove_column :comments, :creation_date
    rename_column :comments, :se_creation_date, :creation_date
  end
end
