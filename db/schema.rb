# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20180120171757) do

  create_table "comments", force: :cascade do |t|
    t.text "body"
    t.text "body_markdown"
    t.integer "comment_id"
    t.text "creation_date"
    t.boolean "edited"
    t.text "link"
    t.integer "owner"
    t.integer "post_id"
    t.text "post_type"
    t.integer "reply_to_user"
    t.integer "score"
  end

  create_table "users", force: :cascade do |t|
    t.integer "accept_rate"
    t.text "display_name"
    t.text "link"
    t.text "profile_image"
    t.integer "reputation"
    t.integer "user_id"
    t.text "type"
  end

end
