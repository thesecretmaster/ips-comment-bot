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

        @fall_through_actions.push(method(:bad_command))

        @reply_actions["tp"] = method(:tp)
        @reply_actions["fp"] = method(:fp)
        @reply_actions["wrongo"] = method(:fp) #fun fp alias
        @reply_actions["rude"] = method(:rude)
        @reply_actions["dbid"] = method(:dbid)
        @reply_actions["feedbacks"] = method(:feedbacks)
        @reply_actions["del"] = method(:del_reply)
        @reply_actions["huh?"] = method(:huh)
        @reply_actions["rescan"] = method(:rescan)
        @reply_actions["report"] = method(:report)

        @howgood_actions["tp"] = method(:howgood_tp) #For tp responses to howgood
        @howgood_actions["fp"] = method(:howgood_fp) #For fp responses to howgood
        @howgood_actions["*"] = method(:howgood_glob) #For * responses to howgood
    end

    def setup_reply_actions
        @reply_actions.each do |command, action|
            @chatter.add_reply_action(command, action, [self])
        end

        @howgood_actions.each do |command, action|
            @chatter.add_reply_action(command, action, [self])
        end
    end

    def setup_mention_actions
        @mention_actions.each do |action|
            @chatter.add_mention_action(action, [self])
        end
    end

    def setup_fall_through_actions
        @fall_through_actions.each do |action|
            @chatter.add_fall_through_reply_action(action, [self])
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
        ["cat", "kitty", "kitties", "kitten", "meow", "purr", "feline"].any? { |cat_name| message.downcase.include? cat_name }
    end

    def tp(replier, msg_id, parent_id, room_id, *args)
        comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
        return if comment.nil?

        comment.tps ||= 0
        comment.tps += 1
        comment.save

        replier.chatter.say "Marked this comment as caught correctly (tp). Currently marked #{comment.tps.to_i}tps/#{comment.fps.to_i}fps. *beep boop* My human overlords won't let me flag that, so you'll have to do it yourself.", room_id
    end
end


def fp(replier, msg_id, parent_id, room_id, *args)
    comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
    return if comment.nil?

    comment.fps ||= 0
    comment.fps += 1
    comment.save
    replier.chatter.say "Marked this comment as caught incorrectly (fp). Currently marked #{comment.tps.to_i}tps/#{comment.fps.to_i}fps", room_id
end

def rude(replier, msg_id, parent_id, room_id, *args)
    comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
    return if comment.nil?

    comment.rude ||= 0
    comment.tps ||= 0
    comment.rude += 1
    comment.tps += 1
    comment.save
    replier.chatter.say("Registered as rude. *beep boop* My human overlords won't let me flag that, so you'll have to do it yourself.", room_id)
end

def dbid(replier, msg_id, parent_id, room_id, *args)
    comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
    return if comment.nil?

    replier.chatter.say("This comment has id #{comment.id} in the database", room_id)
end

def feedbacks(replier, msg_id, parent_id, room_id, *args)
    comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
    return if comment.nil?

    replier.chatter.say("Currently marked #{comment.tps.to_i}tps/#{comment.fps.to_i}fps", room_id)
end

def del_reply(replier, msg_id, parent_id, room_id, *args)
    comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
    return if comment.nil?

    MessageCollection::ALL_ROOMS.message_ids_for(comment).each do |id|
        replier.chatter.delete(id)
    end
end

def huh(replier, msg_id, parent_id, room_id, *args)
    comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
    return if comment.nil?

    matched_regexes = replier.scanner.report_raw(comment["post_type"], comment["body_markdown"])
    # Go through regexes we matched to build reason_text
    reason_text = matched_regexes.map do |regex_match|
        reason = "Matched reason \"#{regex_match.reason.name}\""
        regex = "for regex #{regex_match.regex}"
        "#{reason} #{regex}"
    end.join("\n")

    # If post isn't deleted, check if this was an inactive comment
    if post = replier.seclient.post_exists?(comment.post_id)
        if replier.scanner.timestamp_to_date(post.json["last_activity_date"]) < replier.scanner.timestamp_to_date(comment["creation_date"]) - 30
            reason_text += "Comment was made #{(replier.scanner.timestamp_to_date(comment["creation_date"]) - replier.scanner.timestamp_to_date(post.json["last_activity_date"])).to_i} days after last activity on post\n"
        end
    end

    reason_text += "\nComment has toxicity of #{comment["perspective_score"]}" if comment["perspective_score"].to_f >= 0.7

    replier.chatter.say((reason_text.empty? ? "Comment didn't match any regexes" : reason_text), room_id)
end

def rescan(replier, msg_id, parent_id, room_id, *args)
    db_comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
    return if db_comment.nil?

    if replier.seclient.comment_deleted?(db_comment["comment_id"])
        replier.chatter.say("Comment with id #{db_comment["comment_id"]} was deleted and cannot be rescanned.", room_id)
    else
        replier.scanner.scan_comments(db_comment["comment_id"])
    end
end

def report(replier, msg_id, parent_id, room_id, *report_reason)
    db_comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
    return if db_comment.nil?

    if replier.seclient.comment_deleted?(db_comment["comment_id"])
        replier.chatter.say("Comment with id #{db_comment["comment_id"]} was deleted and cannot be reported.", room_id)
    else
        replier.scanner.custom_report(db_comment, "Reported with custom reason: #{report_reason.join(' ')}")
    end
end

def howgood_tp(replier, msg_id, parent_id, room_id, num_to_display=3)
    hg_comment = MessageCollection::ALL_ROOMS.howgood_for(parent_id.to_i)
    return if hg_comment.nil?

    if !/\A\d+\z/.match(num_to_display) || num_to_display.to_i < 1
        replier.chatter.say("Bad number. Reply to howgood with <comment_type> <num> to print num matches of comment_type where comment types are tp, fp, and *", room_id)
        return
    end

    regex = hg_comment[0]
    types = hg_comment[1]
    comments_to_display = []

    if types == '*'
        comments_to_display = Comment.where("tps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
    else
        comments_to_display = Comment.where(post_type: types).where("tps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
    end

    replier.chatter.say("There are no tp's on that howgood.", room_id) if comments_to_display.count == 0

    #no need to return and prevent this from runnng. It won't do anything if db_comments is empty anyways
    comments_to_display.take(num_to_display).each { |comment| replier.scanner.report_db_comment(comment, should_post_matches: false) }
end

def howgood_fp(replier, msg_id, parent_id, room_id, num_to_display=3)
    hg_comment = MessageCollection::ALL_ROOMS.howgood_for(parent_id.to_i)
    return if hg_comment.nil?

    if !/\A\d+\z/.match(num_to_display) || num_to_display.to_i < 1
        replier.chatter.say("Bad number. Reply to howgood with <comment_type> <num> to print num matches of comment_type where comment types are tp, fp, and *", room_id)
        return
    end

    regex = hg_comment[0]
    types = hg_comment[1]
    comments_to_display = []

    if types == '*'
        comments_to_display = Comment.where("fps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
    else
        comments_to_display = Comment.where(post_type: types).where("fps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
    end

    replier.chatter.say("There are no fp's on that howgood.", room_id) if comments_to_display.count == 0

    #no need to return and prevent this from runnng. It won't do anything if db_comments is empty anyways
    comments_to_display.take(num_to_display).each { |comment| replier.scanner.report_db_comment(comment, should_post_matches: false) }
end

def howgood_glob(replier, msg_id, parent_id, room_id, num_to_display=3)
    hg_comment = MessageCollection::ALL_ROOMS.howgood_for(parent_id.to_i)
    return if hg_comment.nil?

    if !/\A\d+\z/.match(num_to_display) || num_to_display.to_i < 1
        replier.chatter.say("Bad number. Reply to howgood with <comment_type> <num> to print num matches of comment_type where comment types are tp, fp, and *", room_id)
        return
    end

    regex = hg_comment[0]
    types = hg_comment[1]
    comments_to_display = []

    if types == '*'
        comments_to_display = Comment.select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
    else
        comments_to_display = Comment.where(post_type: types).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
    end

    replier.chatter.say("There are no comments on that howgood.", room_id) if comments_to_display.count == 0

    #no need to return and prevent this from runnng. It won't do anything if db_comments is empty anyways
    comments_to_display.take(num_to_display).each { |comment| replier.scanner.report_db_comment(comment, should_post_matches: false) }
end

#TODO: Add a "none" option for howgood at some point. Would work by checking that tps/fps = nil

def bad_command(replier, msg_id, parent_id, room_id, *args)
    db_comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
    hg_comment = MessageCollection::ALL_ROOMS.howgood_for(parent_id.to_i)

    if !db_comment.nil?
        if args.length > 0 #They're not trying to give a command
            #Maybe make conversation back (33% chance)
            replier.chatter.say(":#{msg_id} #{replier.random_response}", room_id) if rand > 0.67
        else
            replier.chatter.say("Invalid feedback type. Valid feedback types are tp, fp, rude, and wrongo", room_id)
        end
    elsif !hg_comment.nil?
        replier.chatter.say("Invalid comment type. Reply to howgood with <comment_type> <num> to print num matches of comment_type where comment types are tp, fp, and *", room_id)
    else
        @logger.debug "That was not a report"
        # replier.chatter.say("That was not a report", room_id)
    end
end

def cat_mentions(replier, msg_id, room_id, message)
    return unless contains_cat(message)

    cat_response = HTTParty.post("https://aws.random.cat/meow")
    case cat_response.code
        when 200 #All good!
            replier.chatter.say(":#{msg_id} #{cat_response.parsed_response["file"]}", room_id)
        when 404
            replier.chatter.say("O noes! Cats not found!", room_id)
        when 500...600
            replier.chatter.say("ZOMG ERROR #{response.code}...and no cats :(", room_id)
    end
end
