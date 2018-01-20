class AddRegexTable < ActiveRecord::Migration[5.1]
  def change
    create_table :regexes do |t|
      t.text :post_type
      t.text :regex
    end
  end
end
