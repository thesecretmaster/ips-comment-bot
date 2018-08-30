require 'htmlentities'

class EscapeAllCommentBodies < ActiveRecord::Migration[5.2]
  def self.up
    htmlentities = HTMLEntities.new
    Comment.all.each do |c|
      c.body = htmlentities.decode c.body
      c.body_markdown = htmlentities.decode c.body_markdown
      c.save
    end
  end
end
