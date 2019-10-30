require 'time'
require './db'

class Commander
    attr_reader :chatter, :seclient, :scanner, :BOT_NAMES, :start_time

    def initialize(chatter, seclient, scanner, bot_names, logger)
        @chatter = chatter
        @seclient = seclient
        @scanner = scanner
        @BOT_NAMES = bot_names
        @logger = logger

        @basic_commands = {}
        @HQ_commands = {}

        @basic_commands["!!/whoami"] = method(:whoami)
        @basic_commands["!!/alive"] = method(:alive)
        @basic_commands["!!/on"] = method(:on)
        @basic_commands["!!/off"] = method(:off)
        @basic_commands["!!/mode"] = method(:mode)
        @basic_commands["!!/help"] = method(:help)
        @basic_commands["!!/notify"] = method(:notify)
        @basic_commands["!!/reports"] = method(:reports)

        @HQ_commands["!!/whitelist"] = method(:whitelistuser)
        @HQ_commands["!!/unwhitelist"] = method(:unwhitelistuser)
        @HQ_commands["!!/whitelisted"] = method(:whitelisted)
        @HQ_commands["!!/notice"] = method(:noticeuser)
        @HQ_commands["!!/unnotice"] = method(:unnoticeuser)
        @HQ_commands["!!/noticed"] = method(:noticedusers)
        @HQ_commands["!!/quota"] = method(:quota)
        @HQ_commands["!!/uptime"] = method(:uptime)
        @HQ_commands["!!/logsize"] = method(:logsize)
        @HQ_commands["!!/howmany"] = method(:howmany)
        @HQ_commands["!!/test"] = method(:test)
        @HQ_commands["!!/howgood"] = method(:howgood)
        @HQ_commands["!!/del"] = method(:del)
        @HQ_commands["!!/add"] = method(:add)
        @HQ_commands["!!/cid"] = method(:cid)
        @HQ_commands["!!/pull"] = method(:pull)
        @HQ_commands["!!/master"] = method(:master)
        @HQ_commands["!!/restart"] = method(:restart)
        @HQ_commands["!!/kill"] = method(:kill)
        @HQ_commands["!!/rev"] = method(:rev)
        @HQ_commands["!!/manscan"] = method(:manscan)
        @HQ_commands["!!/ttscan"] = method(:ttscan)
        @HQ_commands["!!/last"] = method(:last)
        @HQ_commands["!!/regexes"] = method(:regexes)
        @HQ_commands["!!/regexstats"] = method(:regexstats)

        @start_time = Time.now
    end

    def setup_basic_commands
        #For each room, add each basic command
        (@chatter.rooms + [@chatter.HQroom]).each do |room_id|
            @basic_commands.each do |command, action|
                @chatter.add_command_action(room_id, command, action, [])
            end
        end
    end

    def setup_HQ_commands
        @HQ_commands.each do |command, action|
            @chatter.add_command_action(@chatter.HQroom, command, action, [])
        end
    end

    def matches_bot?(botname)
        @logger.debug "Checking if #{botname} matches #{@BOT_NAMES}"
        botname.nil? || botname == '*' || @BOT_NAMES.include?(botname.downcase)
    end

    def isHQ?(room_id)
        room_id == @chatter.HQroom
    end

    def on?(room_id)
        isHQ?(room_id) || Room.find_by(room_id: room_id).on?
    end

    def restart_bot(num_to_post, bundle)
        if bundle == "true"
            say "Updating bundle..."
            log = `bundle install`
            say "Update complete!\n#{"="*32}\n#{log}"
        end
        Kernel.exec("bundle exec ruby comment_scan.rb #{num_to_post.nil? ? @post_on_startup : num_to_post.to_i}")
    end

    def percent_str(numerator, denominator, precision: 8, blank_str: '-')
      return blank_str if denominator.zero?
      "#{(numerator*100.0/denominator).round(precision)}%"
    end

    def to_sizes(filenames)
      filenames.map do |filename|
        full_name = "./#{filename}"
        fsize, ext = File.size(full_name).to_f/(1024**2), "MB"
        {
          file: filename,
          size: fsize,
          ext: ext
        }
      end
    end

    #TODO: consider making some kind of check valid arg that'll return a bool and print "Bad! Arg must be in {X, Y, Z}"
    #      since this is definitely something I do several times below

     def whoami(room_id)
        return unless on?(room_id)

        if isHQ?(room_id) && rand(0...20) == rand(0...20)
            @chatter.say("24601")
        else
            @chatter.say("I go by #{@BOT_NAMES.join(" and ")}", room_id)
        end
    end

    def alive(room_id, bot='*')
        return unless matches_bot?(bot) || !on?(room_id)
        @chatter.say("I'm alive and well :)", room_id)
    end

    def on(room_id, bot='*')
        return unless matches_bot?(bot)
        if Room.find_by(roome_id: room_id).on?
            @chatter.say("I'm already on, silly", room_id)
        else
            @chatter.say("Turning on...", room_id)
            Room.find_by(room_id: room_id).turn_on
        end
    end

    def off(room_id, bot='*')
        return unless matches_bot?(bot)
        if !Room.find_by(room_id: room_id).on?
            @chatter.say("I'm already off, silly", room_id)
        else
            @chatter.say("Turning off...", room_id)
            Room.find_by(room_id: room_id).turn_off
        end
    end

    def mode(room_id, bot='*')
        return unless matches_bot?(bot) && on?(room_id)
        if isHQ?(room_id)
            @chatter.say("I'm in parent mode. I have children in rooms #{@chatter.rooms.flatten.map { |rid| "[#{rid}](https://chat.stackexchange.com/rooms/#{rid})"}.join(", ")}", room_id)
        else
            @chatter.say("I'm in child mode. My parent is in [room #{@chatter.HQroom}](https://chat.stackexchange.com/rooms/#{@chatter.HQroom})", room_id)
        end
    end

    def help(room_id, bot='*')
        return unless matches_bot?(bot) && on?(room_id)
        if isHQ?(room_id)
            @chatter.say(File.read('./hq_help.txt'), room_id)
        else
            @chatter.say(File.read("./help.txt"), room_id)
        end
    end

    def notify(room_id, bot, type, status)
        return unless matches_bot?(bot) && on?(room_id)
        actions = { "regex" => :regex_match,
                     "magic" => :magic_comment}
        if !actions.key?(type)
            @chatter.say("Type must be one of {#{actions.keys.join(", ")}}")
            return
        end
        act = actions[type]

        if !["on", "off"].include? status
            @chatter.say("Status must be one of {on, off}")
            return
        end
        status = {"on" => true, "off" => false}[status]

        @chatter.say("I #{status ? "will" : "won't"} notify you on a #{act}", room_id) unless status.nil? || act.nil?
        Room.find_by(room_id: room_id).update(**{act => status}) unless status.nil? || act.nil?
    end

    def reports(room_id, bot='*')
        return unless matches_bot?(bot) && !on?(room_id)
        room = Room.find_by(room_id: room_id)
        @chatter.say("regex_match: #{!!room.regex_match}\nmagic_comment: #{!!room.magic_comment}", room_id)
    end

    def whitelistuser(room_id, bot, *uids)
        return unless matches_bot?(bot)
        uids.each { |uid| WhitelistedUser.create(user_id: uid) }
        @chatter.say("Whitelisted users #{uids.join(', ')}", room_id)
    end

    def unwhitelistuser(room_id, bot, *uids)
        return unless matches_bot?(bot)
        uids.each { |uid| WhitelistedUser.where(user_id: uid).destroy_all }
        @chatter.say("Unwhitelisted users #{uids.join(', ')}", room_id)
    end

    def whitelisted(room_id, bot='*')
        return unless matches_bot?(bot)
        @chatter.say("Current whitelist: #{WhitelistedUser.all.map(&:user_id).join(', ')}", room_id)
    end

    def noticeuser(room_id, bot, *uids)
        return unless matches_bot?(bot)
        uids.each { |uid| NoticedUser.create(user_id: uid) }
        @chatter.say("Added user(s) #{uids.join(', ')} to the Notice list. Please restart the bot for this to take effect.", room_id)
    end
    
    def unnoticeuser(room_id, bot, *uids)
        return unless matches_bot?(bot)
        uids.each { |uid| NoticedUser.where(user_id: uid).destroy_all }
        @chatter.say("Removed user(s) #{uids.join(', ')} from the Notice list. Please restart the bot for this to take effect.", room_id)
    end
    
    def noticedusers(room_id, bot='*')
        return unless matches_bot?(bot)
        @chatter.say("Current Notice list: #{NoticedUser.all.map(&:user_id).join(', ')}", room_id)
    end

    def quota(room_id, bot='*')
        return unless matches_bot?(bot)
        @chatter.say "#{@seclient.quota} requests remaining"
    end

    def uptime(room_id, bot='*')
        return unless matches_bot?(bot)

        total_secs = (Time.now - @start_time).to_i
        secs = total_secs % 60; total_secs /= 60
        mins = total_secs % 60; total_secs /= 60
        hrs = total_secs % 24; total_secs /= 24
        days = total_secs

        @chatter.say("Up #{days} Days, #{hrs} hours, #{mins} minutes, #{secs} seconds", room_id)
    end

    def logsize(room_id, bot='*')
        return unless matches_bot?(bot)
        uncompressed = to_sizes(Dir['*.log']+Dir['*.log.1']).map do |sizes|
            "#{sizes[:file]}: #{sizes[:size].round(2)}#{sizes[:ext]}"
        end
        compressed = {}
        to_sizes(Dir['*.log*.gz']).each do |size|
            compressed[size[:file].split('.')[0]] ||= 0
            compressed[size[:file].split('.')[0]] += size[:size]
        end
        @chatter.say((uncompressed + compressed.map { |b, s| "#{b}: #{s.round(2)}MB" }).join("\n"), room_id)
    end

    def howmany(room_id, bot='*')
        return unless matches_bot?(bot)
        @chatter.say("I've scanned #{Comment.count} comments", room_id)
    end

    def test(room_id, bot, type, *body)
        return unless matches_bot?(bot)
        if !["q", "a"].include? type[0]
            @chatter.say("Type must be one of {q, a}", room_id)
            return
        end

        @chatter.say((@scanner.report(type, body.join(" ")) || "Didn't match any filters"), room_id)
    end

    def howgood(room_id, bot, type, regex)
        return unless matches_bot?(bot)

        type = 'question' if type == 'q'
        type = 'answer' if type == 'a'
        unless ["question", "answer", "*"].include? type
             @chatter.say("Type must be one of {q, a, question, answer, *}", room_id)
            return
        end

        if type == '*'
            tps = Comment.where("tps >= ?", 1).count { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }.to_f
            fps = Comment.where("fps >= ?", 1).count { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }.to_f
            total = Comment.count { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }.to_f
        else
            tps = Comment.where(post_type: type).where("tps >= ?", 1).count { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }.to_f
            fps = Comment.where(post_type: type).where("fps >= ?", 1).count { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }.to_f
            total = Comment.where(post_type: type).count { |comment| %r{#{regex}}.match(comment.body_markdown.downcase) }.to_f
        end

        tp_msg = [ # Generate tp line
            'tp'.center(6),
            tps.round(0).to_s.center(11),
            percent_str(tps, total).center(14),
            percent_str(tps, Comment.where("tps >= ?", 1).count).center(15),
            percent_str(tps, Comment.count).center(18),
        ].join('|')

        fp_msg = [ # Generate fp line
            'fp'.center(6),
            fps.round(0).to_s.center(11),
            percent_str(fps, total).center(14),
            percent_str(fps, Comment.where("fps >= ?", 1).count).center(15),
            percent_str(fps, Comment.count).center(18),
        ].join('|')

        total_msg = [ # Generate total line
            'Total'.center(6),
            total.round(0).to_s.center(11),
            '-'.center(14),
            '-'.center(15),
            percent_str(total, Comment.count).center(18),
        ].join('|')

        # Generate header line
        header = " Type | # Matched | % of Matched | % of All Type | % of ALL Comments"

        final_output = [ # Add 4 spaces for formatting and newlines
            header, '-'*68, tp_msg, fp_msg, total_msg
        ].join("\n    ")
        msgs = MessageCollection::ALL_ROOMS
        msgs.push_howgood [regex, type], (@chatter.say("    #{final_output}", room_id))
    end

    def del(room_id, bot, type, regex)
        return unless matches_bot?(bot)
        if r = Regex.find_by(post_type: type[0], regex: regex)
            reas_id = r["reason_id"]
            @chatter.say("Destroyed #{r.regex} (post_type #{r.post_type})!", room_id) if r.destroy

            # If there are no other regexes for this reason, destroy the reason too
            if Regex.where(reason_id: reas_id).empty?
                reas = Reason.where(id: reas_id)[0]
                @chatter.say("Destroyed reason: \"#{reas["name"]}\"", room_id) if reas.destroy
            end
        else
            @chatter.say("Could not find regex to destroy", room_id)
        end

    end

    def add(room_id, bot, type, regex, *reason)
        return unless matches_bot?(bot)
        if !["q", "a"].include? type
            commands.chatter.say("Type must be one of {q, a}", room_id)
            return
        end

        begin
            %r{#{regex}}
        rescue RegexpError => e
            @chatter.say("Invalid regex: #{regex}", room_id)
            @chatter.say("    #{e}", room_id)
            return
        end

        if reason = Reason.find_or_create_by(name: reason.join(' '))
            if r = reason.regexes.create(post_type: type[0], regex: regex)
                @chatter.say("Added regex #{r.regex} for post_type #{r.post_type} with reason '#{r.reason.name}'", room_id)
            end
        end
    end

    def cid(room_id, bot, *cids)
        return unless matches_bot?(bot)
        @scanner.scan_comments_from_db(cids)
    end

    def pull(room_id, bot='*', num_to_post=0, update_bundle=false)
        return unless matches_bot?(bot)
        if `git symbolic-ref --short HEAD`.chomp != "master"
            @chatter.say("Pulling is only permitted when running on the master branch. Currently on #{`git rev-parse --abbrev-ref HEAD`.chop}.", room_id)
        else
            `git pull`
            restart_bot(num_to_post, update_bundle)
        end
    end

    def master(room_id, bot='*', *args)
        return unless matches_bot?(bot)
        if `git symbolic-ref --short HEAD`.chomp == "master"
            @chatter.say("I'm already on master!", room_id)
        else
            `git checkout master`
            Kernel.exec("bundle exec ruby comment_scan.rb #{args.empty? ? @post_on_startup : args[0].to_i}")
        end
    end

    def restart(room_id, bot='*', num_to_post=0, update_bundle=false)
        return unless matches_bot?(bot)
        restart_bot(num_to_post, update_bundle)
    end

    def kill(room_id, bot='*')
        return unless matches_bot?(bot)
        `kill -9 $(cat bot.pid)`
    end

    def rev(room_id, bot='*')
        return unless matches_bot?(bot)
        @chatter.say("Currently at rev #{`git rev-parse --short HEAD`.chop} on branch #{`git rev-parse --abbrev-ref HEAD`.chop}", room_id)
    end

    def manscan(room_id, bot, *cids)
        return unless matches_bot?(bot)
        @scanner.scan_comments(cids)
    end

    def ttscan(room_id, bot='*')
        return unless matches_bot?(bot)
        @chatter.say("#{@scanner.time_to_scan} seconds remaning until the next scan", room_id)
    end

    def last(room_id, bot='*', num_comments="1")
        return unless matches_bot?(bot)
        if !/\A\d+\z/.match(num_comments) || num_comments.to_i < 1
            @chatter.say("Bad number. Call last with `!!/last <bot> <num_comments>` where num_commments is >0", room_id)
        end

        @scanner.scan_last_n_comments(num_comments)
    end

    def regexes(room_id, bot='*', reason=nil)
        return unless matches_bot?(bot)
        reasons = (reason.nil? ? Reason.all : Reason.where("name LIKE ?", "%#{reason}%")).map do |r|
            regexes = r.regexes.map { |regex| "- #{regex.post_type}: #{regex.regex}" }
            "#{r.name.gsub(/\(\@(\w*)\)/, '(*\1)')}:\n#{regexes.join("\n")}"
        end
        reasonless_regexes = Regex.where(reason_id: nil).map { |regex| "- #{regex.post_type}: #{regex.regex}" }
        reasons << "Other Regexes:\n#{reasonless_regexes.join("\n")}"
        @chatter.say(reasons.join("\n"), room_id)
    end

    def regexstats(room_id, bot='*', reason=nil)
        return unless matches_bot?(bot)
        #Build array of hashes for each regex containing info to build the stat output
        regexes = (reason.nil? ? Reason.all : Reason.where("name LIKE ?", "%#{reason}%")).map do |r|
            r.regexes.map do |regex| 
                tps = Comment.where(post_type: (regex.post_type == 'a' ? 'answer' : 'question')).where("tps >= ?", 1).count { |comment| %r{#{regex.regex}}.match(comment.body_markdown.downcase) }
                fps = Comment.where(post_type: (regex.post_type == 'a' ? 'answer' : 'question')).where("fps >= ?", 1).count { |comment| %r{#{regex.regex}}.match(comment.body_markdown.downcase) }
                {:effectivePercent => (tps + fps > 0) ? tps/(tps + fps).to_f : 0, 
                    :tps => tps, :fps => fps, :postType => regex.post_type, :regex => regex.regex, :reason => r.name}
            end
        end
        regexes = regexes.flatten.sort_by { |regex| regex[:effectivePercent] } #Order by effectiveness

        #Figure out proper widths for columns
        most_popular_regex = regexes.max { |a, b| a[:tps] + a[:fps] <=> b[:tps] + b[:fps] }
        tpfp_width = (("#{most_popular_regex[:tps] + most_popular_regex[:fps]}".length) * 2) + 4
        percent_width =  regexes.any? { |regex| regex[:tps] != 0 && regex[:fps] == 0 } ? 7 : 6

        #Put it all together...
        @chatter.say regexes.map { |r| 
            [
                "".ljust(4),
                percent_str(r[:tps], r[:tps] + r[:fps],
                        precision: 1, blank_str: "n/a").ljust(percent_width),
                "(#{r[:tps]}/#{r[:tps] + r[:fps]})".ljust(tpfp_width),
                "| #{r[:regex]} (#{r[:postType]} - #{r[:reason]})"
            ].join
        }.join("\n"), room_id
    end
end

