class Init < ActiveRecord::Migration[5.1]
  def change
    create_table :comments do |t|
      t.text :body
      t.text :body_markdown
      t.integer :comment_id
      t.text :creation_date
      t.boolean :edited
      t.text :link
      t.integer :owner
      t.integer :post_id
      t.text :post_type
      t.integer :reply_to_user
      t.integer :score
    end
    create_table :users do |t|
      t.integer :accept_rate
      t.text :display_name
      t.text :link
      t.text :profile_image
      t.integer :reputation
      t.integer :user_id
      t.text :type
    end
  end
end
