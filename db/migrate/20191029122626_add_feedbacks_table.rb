class AddFeedbacksTable < ActiveRecord::Migration[5.2]
  def change
    create_table :chat_user do |c|
        c.text :name
        c.bigint :user_id
    end

    create_table :feedbacks do |f|
      f.integer :feedback_type_id
      f.integer :comment_id #DB comment!
      f.bigint :chat_user_id

      f.timestamps
    end

    create_table :feedback_typedefs do |f|
      f.text :feedback
    end

    FeedbackTypedef.create(feedback: "tp")
    FeedbackTypedef.create(feedback: "fp")
    FeedbackTypedef.create(feedback: "rude")
  end
end