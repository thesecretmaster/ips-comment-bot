require './db'
require 'httparty'
require 'htmlentities'

class Replier
    attr_reader :chatter, :scanner, :seclient, :BOT_NAMES

    def initialize(chatter, seclient, scanner, bot_names, logger)
        @chatter = chatter
        @scanner = scanner
        @seclient = seclient
        @BOT_NAMES = bot_names
        @logger = logger

        @mc_replies = {}
        @hg_replies = {}

        @mention_actions = []
        @fall_through_actions = []
        @reply_actions = {}
        @howgood_actions = {}

        @mention_actions.push(method(:cat_mentions))
        @mention_actions.push(method(:dog_mentions))

        @fall_through_actions.push(method(:bad_command))

        @reply_actions["dbid"] = method(:dbid)
        @reply_actions["del"] = method(:del_reply)
        @reply_actions["feedbacks"] = method(:feedbacks)
        @reply_actions["fp"] = method(:fp)
        @reply_actions["huh?"] = method(:huh)
        @reply_actions["pewpew"] = method(:tp) #fun tp alias
        @reply_actions["report"] = method(:report)
        @reply_actions["rescan"] = method(:rescan)
        @reply_actions["rude"] = method(:rude)
        @reply_actions["tp"] = method(:tp)
        @reply_actions["wrongo"] = method(:fp) #fun fp alias

        @howgood_actions["tp"] = method(:howgood_tp) #For tp responses to howgood
        @howgood_actions["fp"] = method(:howgood_fp) #For fp responses to howgood
        @howgood_actions["*"] = method(:howgood_glob) #For * responses to howgood
    end

    def setup_reply_actions
        @reply_actions.each do |command, action|
            @chatter.add_reply_action(command, action, [])
        end

        @howgood_actions.each do |command, action|
            @chatter.add_reply_action(command, action, [])
        end
    end

    def setup_mention_actions
        @mention_actions.each do |action|
            @chatter.add_mention_action(action, [])
        end
    end

    def setup_fall_through_actions
        @fall_through_actions.each do |action|
            @chatter.add_fall_through_reply_action(action, [])
        end
    end

    def show_first_n_comments(db_comments, num_to_display)
        # Pull comment_id's from the first num_to_display comments we matched to pass to scan
        db_comments.take(num_to_display).each { |comment| @scanner.repot_db_comment(comment, should_post_matches: true) }
    end

    def random_response
      responses = ["Ain't that the truth.",
                   "You're telling me.",
                   "Yep. That's about the size of it.",
                   "That's what I've been saying for $(AGE_OF_BOT)!",
                   "What else is new?",
                   "For real?",
                   "Humans, amirite?"]

      return responses[rand(responses.length)]
    end

    def contains_cat(message)
        ["cat", "kitty", "kitties", "kitten", "kitteh", "meow", "purr", "feline"].any? { |cat_name| message.downcase.include? cat_name }
    end

    def contains_dog(message)
        ["dog", "pup", "woof", "bark", "bow-wow", "best friend"].any? { |dog_name| message.downcase.include? dog_name }
    end

    def animals_on?(room_id)
      room_id == @chatter.HQroom || Room.find_by(room_id: room_id).animals 
    end


    def record_feedback(feedback_id, parent_id, chat_user, room_id)
        comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
        return false if comment.nil?

        comment.tps ||= 0
        comment.fps ||= 0
        comment.rude ||= 0

        existing_feedback = Feedback.find_by(comment_id: comment.id, chat_user_id: chat_user.id)

        if existing_feedback.nil? #Create new feedback
            Feedback.create(comment_id: comment.id, chat_user_id: chat_user.id, feedback_type_id: feedback_id, room_id: room_id)
        elsif existing_feedback.feedback_type_id #If one exists, then undo it
            comment.remove_feedback(existing_feedback.feedback_type_id)

            if existing_feedback.feedback_type_id == feedback_id #They're only trying to undo
                existing_feedback.delete
                @chatter.say "Un-#{FeedbackTypedef.feedback_name(feedback_id)}'ed this comment. Currently marked #{comment.tps.to_i}tps/#{comment.fps.to_i}fps."
                comment.save
                return
            end
        end

        result_txt = ''
        comment.add_feedback(feedback_id)

        case feedback_id
        when FeedbackTypedef.tp
            result_txt = "Marked this comment as flaggable (tp). Currently marked #{comment.tps.to_i}tps/#{comment.fps.to_i}fps. *beep boop* My human overlords won't let me flag that, so you'll have to do it yourself."
        when FeedbackTypedef.fp
            result_txt = "Marked this comment as not flag-worthy (fp). Currently marked #{comment.tps.to_i}tps/#{comment.fps.to_i}fps"
        when FeedbackTypedef.rude
            result_txt = "Registered as rude and flaggable (tp). *beep boop* My human overlords won't let me flag that, so you'll have to do it yourself."
        end

        if !existing_feedback.nil? #Feedback switch
            result_txt = "Switching feedback from #{FeedbackTypedef.feedback_name(existing_feedback.feedback_type_id)} to #{FeedbackTypedef.feedback_name(feedback_id)}. Currently marked #{comment.tps.to_i}tps/#{comment.fps.to_i}fps"
            existing_feedback.feedback_type_id = feedback_id
            existing_feedback.save
        end

        @chatter.say(result_txt, room_id)
        return true
    end

    def tp(msg_id, parent_id, chat_user, room_id, *args)
        record_feedback(FeedbackTypedef.tp, parent_id, chat_user, room_id)
    end

    def fp(msg_id, parent_id, chat_user, room_id, *args)
        record_feedback(FeedbackTypedef.fp, parent_id, chat_user, room_id)
    end

    def rude(msg_id, parent_id, chat_user, room_id, *args)
        record_feedback(FeedbackTypedef.rude, parent_id, chat_user, room_id)
    end

    def dbid(msg_id, parent_id, chat_user, room_id, *args)
        comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
        return false if comment.nil?

        @chatter.say("This comment has id #{comment.id} in the database", room_id)
        return true
    end

    def feedbacks(msg_id, parent_id, chat_user, room_id, *args)
        comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
        return false if comment.nil?

        @chatter.say("Currently marked #{comment.tps.to_i}tps/#{comment.fps.to_i}fps/#{comment.rude.to_i}rudes", room_id)
        return true
    end

    def del_reply(msg_id, parent_id, chat_user, room_id, *args)
        comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
        return false if comment.nil?

        MessageCollection::ALL_ROOMS.message_ids_for(comment).each do |id|
            @chatter.delete(id)
        end
        return true
    end

    def huh(msg_id, parent_id, chat_user, room_id, *args)
        comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
        return false if comment.nil?

        matched_regexes = @scanner.report_raw(comment["post_type"], comment["body_markdown"])
        # Go through regexes we matched to build reason_text
        reason_text = matched_regexes.map do |regex_match|
            reason = "Matched reason \"#{regex_match.reason.name}\""
            regex = "for regex #{regex_match.regex}"
            "#{reason} #{regex}"
        end.join("\n")

        # If post isn't deleted, check if this was an inactive comment
        if post = @seclient.post_exists?(comment.post_id)
            if @scanner.timestamp_to_date(post.json["last_activity_date"]) < @scanner.timestamp_to_date(comment["creation_date"]) - 30
                reason_text += "\nComment was made #{(@scanner.timestamp_to_date(comment["creation_date"]) - @scanner.timestamp_to_date(post.json["last_activity_date"])).to_i} days after last activity on post\n"
            end
        end

        reason_text += "\nComment has toxicity of #{comment["perspective_score"]}" if comment["perspective_score"].to_f >= 0.7

        @chatter.say((reason_text.empty? ? "Comment didn't match any regexes" : reason_text), room_id)
        return true
    end

    def rescan(msg_id, parent_id, chat_user, room_id, *args)
        db_comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
        return false if db_comment.nil?

        if @seclient.comment_deleted?(db_comment["comment_id"])
            @chatter.say("Comment with id #{db_comment["comment_id"]} was deleted and cannot be rescanned.", room_id)
        else
            @scanner.scan_comments(db_comment["comment_id"])
        end
        return true
    end

    def report(msg_id, parent_id, chat_user, room_id, *report_reason)
        return false if room_id != @chatter.HQroom

        db_comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
        return false if db_comment.nil?

        if @seclient.comment_deleted?(db_comment["comment_id"])
            @chatter.say("Comment with id #{db_comment["comment_id"]} was deleted and cannot be reported.", room_id)
        else
            @scanner.custom_report(db_comment, "Reported with custom reason: \"#{report_reason.join(' ')}\" by #{chat_user.name}")
            @chatter.say("Successfully reported comment ##{db_comment["comment_id"]} with custom reason \"#{report_reason.join(' ')}\"")
        end
        return true
    end

    def howgood_tp(msg_id, parent_id, chat_user, room_id, num_to_display=3)
        hg_comment = MessageCollection::ALL_ROOMS.howgood_for(parent_id.to_i)
        return false if hg_comment.nil?

        if num_to_display.to_i.to_s != num_to_display.to_s || (num_to_display = num_to_display.to_i) < 1
            @chatter.say("Bad number. Reply to howgood with <comment_type> <num> to print num matches of comment_type where comment types are tp, fp, and *", room_id)
            return true
        end

        regex = hg_comment[0]
        types = hg_comment[1]
        comments_to_display = []

        if types == '*'
            comments_to_display = Comment.where("tps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
        else
            comments_to_display = Comment.where(post_type: types).where("tps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
        end

        @chatter.say("There are no tp's on that howgood.", room_id) if comments_to_display.count == 0

        #no need to return and prevent this from runnng. It won't do anything if db_comments is empty anyways
        comments_to_display.take(num_to_display).each do |comment|
            @scanner.report_db_comment(comment, should_post_matches: false)
        end
        return true
    end

    def howgood_fp(msg_id, parent_id, chat_user, room_id, num_to_display=3)
        hg_comment = MessageCollection::ALL_ROOMS.howgood_for(parent_id.to_i)
        return false if hg_comment.nil?

        if num_to_display.to_i.to_s != num_to_display.to_s || (num_to_display = num_to_display.to_i) < 1
            @chatter.say("Bad number. Reply to howgood with <comment_type> <num> to print num matches of comment_type where comment types are tp, fp, and *", room_id)
            return true
        end

        regex = hg_comment[0]
        types = hg_comment[1]
        comments_to_display = []

        if types == '*'
            comments_to_display = Comment.where("fps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
        else
            comments_to_display = Comment.where(post_type: types).where("fps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
        end

        @chatter.say("There are no fp's on that howgood.", room_id) if comments_to_display.count == 0

        #no need to return and prevent this from runnng. It won't do anything if db_comments is empty anyways
        comments_to_display.take(num_to_display).each do |comment|
            @scanner.report_db_comment(comment, should_post_matches: false)
        end
        return true
    end

    def howgood_glob(msg_id, parent_id, chat_user, room_id, num_to_display=3)
        hg_comment = MessageCollection::ALL_ROOMS.howgood_for(parent_id.to_i)
        return false if hg_comment.nil?

        if num_to_display.to_i.to_s != num_to_display.to_s || (num_to_display = num_to_display.to_i) < 1
            @chatter.say("Bad number. Reply to howgood with <comment_type> <num> to print num matches of comment_type where comment types are tp, fp, and *", room_id)
            return true
        end

        regex = hg_comment[0]
        types = hg_comment[1]
        comments_to_display = []

        if types == '*'
            comments_to_display = Comment.select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
        else
            comments_to_display = Comment.where(post_type: types).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
        end

        @chatter.say("There are no comments on that howgood.", room_id) if comments_to_display.count == 0

        #no need to return and prevent this from runnng. It won't do anything if db_comments is empty anyways
        comments_to_display.take(num_to_display).each do |comment|
            @scanner.report_db_comment(comment, should_post_matches: false)
        end
        return true
    end

    #TODO: Add a "none" option for howgood at some point. Would work by checking that tps/fps = nil

    def bad_command(msg_id, parent_id, chat_user, room_id, *args)
        db_comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
        hg_comment = MessageCollection::ALL_ROOMS.howgood_for(parent_id.to_i)

        if !db_comment.nil?
            if args.length > 0 #They're not trying to give a command
                #Maybe make conversation back (15% chance)
                @chatter.say(":#{msg_id} #{random_response}", room_id) if rand > 0.85
            else
                @chatter.say("Invalid feedback type. Valid feedback types are tp, fp, rude, and wrongo", room_id)
            end
        elsif !hg_comment.nil?
            @chatter.say("Invalid comment type. Reply to howgood with <comment_type> <num> to print num matches of comment_type where comment types are tp, fp, and *", room_id)
        else
            #That was not a report
        end
    end

    def cat_mentions(msg_id, chat_user, room_id, message)
        return false unless contains_cat(message) && animals_on?(room_id)

        cat_response = HTTParty.post("https://aws.random.cat/meow")
        case cat_response.code
            when 200 #All good!
                @chatter.say(":#{msg_id} #{cat_response.parsed_response["file"]}", room_id)
            when 404
                @chatter.say("O noes! Cats not found!", room_id)
            when 500...600
                @chatter.say("ZOMG ERROR #{cat_response.code}...and no cats :(", room_id)
        end
        return true
    end

    def dog_mentions(msg_id, chat_user, room_id, message)
        return false unless contains_dog(message) && animals_on?(room_id)

        dog_response = HTTParty.get("https://dog.ceo/api/breeds/image/random")
        case dog_response.code
            when 200 #All good!
                @chatter.say(":#{msg_id} #{dog_response.parsed_response["message"]}", room_id)
            when 404
                @chatter.say("O noes! Dogs not found!", room_id)
            when 500...600
                @chatter.say("ZOMG ERROR #{dog_response.code}...and no dogs :(", room_id)
            else
                begin
                    if dog_response.parsed_response["status"] == "error"
                        @chatter.say("dog.ceo API returned error: #{dog_response.parsed_response["message"]}")
                    end
                rescue Exception => e
                    #Just make sure we don't break everything for this...
                end
        end
        return true
    end
end


