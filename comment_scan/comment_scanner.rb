require './db'
require_relative 'message_collection'

class CommentScanner
    attr_reader :seclient, :chatter, :time_to_scan

    def initialize(seclient, chatter, post_all_comments, ignore_users, logger, hot_secs: 10800, 
                    hot_comment_num: 10, perspective_key: '', perspective_log: Logger.new('/dev/null'))
        @seclient = seclient
        @chatter = chatter
        @post_all_comments = post_all_comments
        @ignore_users = ignore_users
        @logger = logger
        @HOT_SECONDS = hot_secs
        @HOT_COMMENT_NUM = hot_comment_num
        @perspective_key = perspective_key
        @perspective_log = perspective_log

        @time_to_scan = 60
        @latest_comment_date = @seclient.latest_comment_date.to_i+1 unless @seclient.latest_comment_date.nil?
    end

    def scan_new_comments
        new_comments = @seclient.comments_after_date(@latest_comment_date)
        @latest_comment_date = new_comments[0].json["creation_date"].to_i+1 if new_comments.any? && !new_comments[0].nil?
        scan_se_comments([new_comments])
        check_for_hot_post([new_comments])
    end

    def tick
        (@time_to_scan = 60; return false) if (@time_to_scan -= 1) <= 0
        return true
    end

    def check_for_hot_post(new_comments)
        #Only check each post once, so make unique by post ID
        new_comments.flatten.uniq(&:post_id).each do |comment|
            continue unless post = @seclient.post_exists?(comment.post_id) # If post was deleted, skip it
            comments_on_post = Comment.
                                    where(post_id: comment.post_id).
                                    where("creation_date >= :date", date: Time.at(comment.creation_date - @HOT_SECONDS).to_datetime)

            if comments_on_post.count >= @HOT_COMMENT_NUM && !MessageCollection::ALL_ROOMS.hot_post_recorded?(post.id)
                report_hot_post(post.link, post.title, comments_on_post.count, @HOT_SECONDS/60/60)
                MessageCollection::ALL_ROOMS.push_hot_post(post.id)
            end
        end
    end

    def report_hot_post(post_link, post_title, comment_num, hr_num)
        (@chatter.rooms + [@chatter.HQroom]).flatten.each do |room_id|
            room = Room.find_by(room_id: room_id)
            next unless (room_id == @chatter.HQroom) || (!room.nil? && room.on? && room.regex_match)

            @chatter.say("**Post is currently hot!** With #{comment_num} comments in the last #{hr_num} hours: [#{post_title}](#{post_link})", room_id)
        end
    end

    def scan_comments_from_db(*comment_ids)
        comment_ids.flatten.each do |comment_id|
            scan_comment_from_db(comment_id)
        end
    end

    def scan_comment_from_db(comment_id)
        dbcomment = Comment.find_by(comment_id: comment_id)

        if dbcomment.nil?
            @chatter.say("**BAD ID:** No comment exists in the database for id: #{comment_id}")
        else
            report_db_comments(dbcomment, should_post_matches: false)
        end
    end

    def scan_comments(*comment_ids)
        comment_ids.flatten.each do |comment_id|
            comment = seclient.comment_with_id(comment_id)

            if comment.nil? #Didn't actually scan
                @chatter.say("**BAD ID:** No comment exists for id: #{comment_id} (it may have been deleted)")
                next
            end

            scan_se_comment(comment)
        end
    end

    def scan_se_comments(comments)
        comments.flatten.each do |comment|
            scan_se_comment(comment)
        end
    end

    def scan_se_comment(comment)
        body = comment.body_markdown
        toxicity = perspective_scan(body).to_f

        if dbcomment = Comment.record_comment(comment, @logger, perspective_score: toxicity)
            report_db_comments(dbcomment, should_post_matches: true)
        end
    end

    def scan_last_n_comments(num_comments)
        if num_comments.to_i > 0
            comments_to_scan = @seclient.comments[0..(num_comments.to_i - 1)]
            scan_se_comments(comments_to_scan)
        end
    end

    def report_db_comments(*comments, should_post_matches: true)
        comments.flatten.each do |comment| 
            report_db_comment(comment, should_post_matches: should_post_matches)
        end
    end

    def custom_report(dbcomment, custom_reason)
        report_db_comment(dbcomment, custom_report: true, custom_text: custom_reason)
    end

    def report_db_comment(comment, should_post_matches: true, custom_report: false, custom_text: "")
        user = User.where(id: comment["owner_id"])
        user = user.any? ? user.first : false # if user was deleted, set it to false for easy checking

        @logger.debug "Grab metadata..."

        author = user ? user.display_name : "(removed)"
        author_link = user ? "[#{author}](#{user.link})" : "(removed)"
        rep = user ? "#{user.reputation} rep" : "(removed) rep"

        #ts = ts_for(comment["creation_date"]

        @logger.debug "Grab post data/build message to post..."

        msg = "##{comment["post_id"]} #{author_link} (#{rep})"

        @logger.debug "Analyzing post..."

        post_inactive = false # Default to false in case we can't access post
        post = [] # so that we can use this later for whitelisted users

        if post = @seclient.post_exists?(comment["post_id"]) # If post wasn't deleted, do full print
            author = user_for post.owner
            editor = user_for post.last_editor
            creation_ts = ts_for post.json["creation_date"]
            edit_ts = ts_for post.json["last_edit_date"]
            type = post.type[0].upcase
            closed = post.json["close_date"]

            post_inactive = timestamp_to_date(post.json["last_activity_date"]) < timestamp_to_date(comment["creation_date"]) - 30

            msg += " | [#{type}: #{post.title}](#{post.link}) #{'[c]' if closed} (score: #{post.score}) | posted #{creation_ts} by #{author}"
            msg += " | edited #{edit_ts} by #{editor}" unless edit_ts.empty? || editor.empty?
        end

        # toxicity = perspective_scan(body, perspective_key: settings['perspective_key']).to_f
        toxicity = comment["perspective_score"].to_f

        @logger.debug "Building message..."
        msg += " | Toxicity #{toxicity}"
        # msg += " | Has magic comment" if !post_exists?(cli, comment["post_id"]) and has_magic_comment? comment, post
        msg += " | High toxicity" if toxicity >= 0.7
        msg += " | Comment on inactive post" if post_inactive
        msg += " | tps/fps: #{comment["tps"].to_i}/#{comment["fps"].to_i}"

        @logger.debug "Building comment body..."

        # If the comment exists, we can just post the link and ChatX will do the rest
        # Else, make a quote manually with just the body (no need to be fancy, this must be old)
        # (include a newline in the manual string to lift 500 character limit in chat)
        # TODO: Chat API is truncating to 500 characters right now even though we're good to post more. Fix this.
        comment_text_to_post = @seclient.comment_deleted?(comment["comment_id"]) ? ("\n> " + comment["body"]) : comment["link"]

        @logger.debug "Check reasons..."

        report_text = custom_report ? custom_text : report(comment["post_type"], comment["body_markdown"])
        reasons = report_raw(comment["post_type"], comment["body_markdown"]).map(&:reason)

        if reasons.map(&:name).include?('abusive') || reasons.map(&:name).include?('offensive')
            comment_text_to_post = "⚠️☢️\u{1F6A8} [Offensive/Abusive Comment](#{comment["link"]}) \u{1F6A8}☢️⚠️"
        end

        msgs = MessageCollection::ALL_ROOMS

        @logger.debug "Post chat message..."

        if @post_all_comments
            msgs.push comment, @chatter.say(comment_text_to_post)
            msgs.push comment, @chatter.say(msg)
            msgs.push comment, @chatter.say(report_text) if report_text
        elsif !@post_all_comments && (report_text) && (post && !@ignore_users.map(&:to_i).push(post.owner.id).flatten.include?(user.user_id.to_i))
            msgs.push comment, @chatter.say(comment_text_to_post)
            msgs.push comment, @chatter.say(msg)
            msgs.push comment, @chatter.say(report_text) if report_text
        end

        @chatter.rooms.flatten.each do |room_id|
            room = Room.find_by(room_id: room_id)
            next unless (!room.nil? && room.on?)

            should_post_message = ((
                                        # (room.magic_comment && has_magic_comment?(comment, post)) ||
                                        (room.regex_match && report_text) ||
                                        toxicity >= 0.7 || # I should add a room property for this
                                        post_inactive # And this
                                    ) && should_post_matches && user &&
                                      post && !@ignore_users.map(&:to_i).push(post.owner.id).map(&:to_i).include?(user["user_id"].to_i) &&
                                      (user['user_type'] != 'moderator')
                                  ) || custom_report

            if should_post_message
                msgs.push comment, @chatter.say(comment_text_to_post, room_id)
                msgs.push comment, @chatter.say(msg, room_id)
                msgs.push comment, @chatter.say(report_text, room_id) if room.regex_match && report_text
            end
        end
    end

    def report_raw(post_type, comment_body)
      regexes = Regex.where(post_type: post_type[0].downcase)
      regexes.select do |regex|
        %r{#{regex.regex}}.match? comment_body.downcase
      end
    end

    def report(post_type, comment_body)
      matching_regexes = report_raw(post_type, comment_body)
      return "Matched regex(es) #{matching_regexes.map { |r| r.reason.nil? ? r.regex : r.reason.name }.uniq }" unless matching_regexes.empty?
    end

    def has_magic_comment?(comment, post)
      !comment.body_markdown.include?("https://interpersonal.meta.stackexchange.com/q/1644/31") &&
      post.comments.any? do |c|
        c.body_markdown.include?("https://interpersonal.meta.stackexchange.com/q/1644/31")
      end
    end

    def ts_for(ts)
      return "" if ts.nil?
      ts = (Time.new - Time.at(ts.to_i)).to_i
      return "" if ts < 0
      if ts < 60
        "#{ts} seconds ago"
      elsif ts/60 < 60
        "#{ts/60} minutes ago"
      elsif ts/(60**2) < 60
        "#{ts/(60**2)} hours ago"
      else
        "#{ts/(24*60*60)} days ago"
      end
    end

    def timestamp_to_date(timestamp)
      Time.at(timestamp.to_i).to_date
    end

    def user_for(author)
      #return "" unless author.is_a? SE::API::User
      name = author.name
      link = author.link&.gsub(/(^.*u[sers]{4}?\/\d*)\/.*$/, '\1')&.gsub("/users/", "/u/")
      rep = author.reputation
      return "(deleted user)" if name.nil? && link.nil? && rep.nil?
      "[#{name}](#{link}) (#{rep} rep)"
    end

    def perspective_scan(text)
        return 'NoKey' unless @perspecitve_key

        @logger.debug "Perspective scan..."
        response = HTTParty.post("https://commentanalyzer.googleapis.com/v1alpha1/comments:analyze?key=#{@perspective_key}",
        :body => {
            "comment" => {
                text: text,
                type: 'PLAIN_TEXT' # This should eventually be HTML, when perspective supports it
            },
            "context" => {}, # Not yet supported
            "requestedAttributes" => {
                'TOXICITY' => {
                    scoreType: 'PROBABILITY',
                    scoreThreshold: 0
                }
            },
            "languages" => ["en"],
            "doNotStore" => true,
            "sessionId" => '' # Use this if there are multiple bots running
        }.to_json,
        :headers => { 'Content-Type' => 'application/json' } )

        @perspective_log.info response
        @perspective_log.info response.dig("attributeScores")
        @perspective_log.info response.dig("attributeScores", "TOXICITY")
        @perspective_log.info response.dig("attributeScores", "TOXICITY", "summaryScore")
        @perspective_log.info response.dig("attributeScores", "TOXICITY", "summaryScore", "value")

        response.dig("attributeScores", "TOXICITY", "summaryScore", "value")
    end

end
