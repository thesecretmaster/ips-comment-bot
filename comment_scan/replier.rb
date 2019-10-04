require './db'

class Replier
    attr_reader :chatter, :scanner, :seclient, :BOT_NAMES

    def initialize(chatter, seclient, scanner, bot_names)
        @chatter = chatter
        @scanner = scanner
        @seclient = seclient
        @BOT_NAMES = bot_names

        @mc_replies = Hash.new()
        @hg_replies = Hash.new()

        @mention_actions = []
        @reply_actions = Hash.new()

        @mention_actions.push(method(:cat_mentions))

        @reply_actions["tp"] = method(:tp)
        @reply_actions["fp"] = method(:fp)
        @reply_actions["wrongo"] = method(:fp) #fun fp alias
        @reply_actions["rude"] = method(:rude)
        @reply_actions["dbid"] = method(:dbid)
        @reply_actions["feedbacks"] = method(:feedbacks)
        @reply_actions["del"] = method(:del)
        @reply_actions["huh?"] = method(:huh)
        @reply_actions["rescan"] = method(:rescan)
        @reply_actions["test"] = method(:tester)
    end

    def setup_reply_actions()
        @reply_actions.each do |command, action|
            @chatter.add_reply_action(command, action, [self])
        end
    end

    def setup_mention_actions()
        @mention_actions.each do |action|
            @chatter.add_mention_action(action, [self])
        end
    end

end

def tp(replier, msg_id, parent_id, room_id, *args)
    comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
    return if comment.nil?

    comment.tps ||= 0
    comment.tps += 1
    comment.save
    replier.chatter.say "Marked this comment as caught correctly (tp). Currently marked #{comment.tps.to_i}tps/#{comment.fps.to_i}fps. *beep boop* My human overlords won't let me flag that, so you'll have to do it yourself.", room_id
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

def del(replier, msg_id, parent_id, room_id, *args)
    comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
    return if comment.nil?

    MessageCollection::ALL_ROOMS.message_ids_for(comment).each do |msg_id|
        replier.chatter.delete(msg_id)
    end
end

def huh(replier, msg_id, parent_id, room_id, *args)
    comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
    return if comment.nil?

    matched_regexes = report_raw(comment["post_type"], comment["body_markdown"])
    # Go through regexes we matched to build reason_text
    reason_text = matched_regexes.map do |regex_match|
        reason = "Matched reason \"#{regex_match.reason.name}\""
        regex = "for regex #{regex_match.regex}"
        "#{reason} #{regex}"
    end.join("\n")

    # If post isn't deleted, check if this was an inactive comment
    if post = replier.seclient.post_exists?(comment.post_id)
        if timestamp_to_date(post.json["last_activity_date"]) < timestamp_to_date(comment["creation_date"]) - 30
            reason_text += "Comment was made #{(timestamp_to_date(comment["creation_date"]) - timestamp_to_date(post.json["last_activity_date"])).to_i} days after last activity on post\n"
        end
    end

    reason_text += "\nComment has toxicity of #{comment["perspective_score"]}" if comment["perspective_score"].to_f >= 0.7

    replier.chatter.say((reason_text.empty? ? "Comment didn't match any regexes" : reason_text), room_id)
end

def rescan(replier, msg_id, parent_id, room_id, *args)
    db_comment = MessageCollection::ALL_ROOMS.comment_for(parent_id.to_i)
    return if db_comment.nil?

    se_comment = replier.seclient.comment_with_id(db_comment["comment_id"])
    if se_comment.nil?
        replier.chatter.say("Comment with id #{db_comment["comment_id"]} was deleted and cannot be rescanned.", room_id)
    else
        replier.scanner.scan_se_comment(se_comment)
    end
end

          #when 'rescan'
def tester(replier, msg_id, parent_id, room_id, *args)
    replier.chatter.say ":#{msg_id} you dare talk back to me?", room_id
end

def cat_mentions(replier, msg_id, room_id, message)
    return unless ["cat", "kitty", "kitties", "kitten"].any? { |cat_name| message.downcase.include? cat_name }

    cat_pic = HTTParty.post("https://aws.random.cat/meow").parsed_response.first.second
    replier.chatter.say(":#{msg_id} #{cat_pic}", room_id)
end

  #on 'reply' do |msg, room_id|
    #begin
      #if msg.hash.include? 'parent_id'
        #mc_comment = MessageCollection::ALL_ROOMS.comment_for(msg.hash['parent_id'].to_i)
        #hg_comment = MessageCollection::ALL_ROOMS.howgood_for(msg.hash['parent_id'].to_i)
        #comment = mc_comment
        #if !comment.nil?
          #comment = Comment.find_by(comment_id: comment.id) if comment.is_a? SE::API::Comment
          #reply_args = msg.body.split(' ')
          #case reply_args[1].downcase
          #else
            #if reply_args.length > 2 #They're not trying to give a command
              ##Maybe make conversation back (33% chance)
              #cb.say ":#{msg.id} #{random_response}", room_id if rand() > 0.67
            #else
              #cb.say "Invalid feedback type. Valid feedback types are tp, fp, rude, and wrongo", room_id
            #end
          #end
          #comment.save
        #elsif !hg_comment.nil?
          #regex = hg_comment[0]
          #types = hg_comment[1]

          #params_passed = msg.body.downcase.split(' ')
          #num_to_display = 3
          #if params_passed.count >= 3
            #if !/\A\d+\z/.match(params_passed[2]) || params_passed[2].to_i < 1
              #cb.say "Bad number. Reply to howgood with <comment_type> <num> to print num matches of comment_type where comment types are tp, fp, and *", room_id
              #next
            #end
            #num_to_display = params_passed[2].to_i
          #end

          #comments_to_display = []

          #case params_passed[1]
          #when 'tp'
            #if types == '*'
              #comments_to_display = Comment.where("tps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            #else
              #comments_to_display = Comment.where(post_type: types).where("tps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            #end
          #when 'fp'
            #if types == '*'
              #comments_to_display = Comment.where("fps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            #else
              #comments_to_display = Comment.where(post_type: types).where("fps >= ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            #end
          #when '*'
            #if types == '*'
              #comments_to_display = Comment.select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            #else
              #comments_to_display = Comment.where(post_type: types).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
            #end
          ## when 'none'
          ### TODO: Would love to have this functionality, but for whatever reason this condition always matches nothing. Need to bug crestmaster about this.
          ###        That being said I'll probably pull request first and then figure this out as an add on...
          ##
          ##   if types == '*'
          ##     comments_to_display = Comment.where("fps < ?", 1).where("tps < ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
          ##   else
          ##     comments_to_display = Comment.where(post_type: type).where("fps < ?", 1).where("tps < ?", 1).select { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }
          ##   end
          #else
            #cb.say "Invalid comment type. Reply to howgood with <comment_type> <num> to print num matches of comment_type where comment types are tp, fp, and *", room_id
            #next
          #end

          #if comments_to_display.count == 0
            #cb.say "There are no " + params_passed[1] + "'s on that howgood.", room_id
            #next
          #end

          ## puts "Got passed: " + params_passed.to_s
          ## puts "Howgood with Regex: " + regex.to_s
          ## puts "Howgood with Types: " + types.to_s
          ## puts "Found the list of comments to display:"
          ## puts
          ## puts comments_to_display.take(num_to_display).to_s

          ## Pull comment_id's from the first num_to_display comments we matched to pass to scan
          #comments_to_display.take(num_to_display).each {
            #|comment|
            #report_comments(comment, cli: cli, settings: settings, cb: cb, should_post_matches: false)
          #}
        #else
          #puts "That was not a report"
          ## cb.say "That was not a report", room_id
        #end
      #end
    #rescue Exception => e
      #cb.say "Got excpetion ```#{e}``` processing your response", room_id
    #end
  #end