class AddReasons < ActiveRecord::Migration[5.1]
  def change
    add_column :regexes, :reason_id, :integer

    create_table :reasons do |t|
      t.text :name
      t.text :description
    end
  end
end
