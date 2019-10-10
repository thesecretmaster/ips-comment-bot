require 'time'
require './db'

class Commander
    attr_reader :chatter, :seclient, :scanner, :BOT_NAMES, :start_time

    def initialize(chatter, seclient, scanner, bot_names)
        @chatter = chatter
        @seclient = seclient
        @scanner = scanner
        @BOT_NAMES = bot_names

        @basic_commands = Hash.new()
        @HQ_commands = Hash.new()

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

    def setup_basic_commands()
        #For each room, add each basic command
        (@chatter.rooms + [@chatter.HQroom]).each do |room_id|
            @basic_commands.each do |command, action|
                @chatter.add_command_action(room_id, command, action, [self])
            end
        end
    end

    def setup_HQ_commands()
        @HQ_commands.each do |command, action|
            @chatter.add_command_action(@chatter.HQroom, command, action, [self])
        end
    end

    def matches_bot?(botname)
        puts "Checking if #{botname} matches #{@BOT_NAMES}"
        botname.nil? || botname == '*' || @BOT_NAMES.include?(botname.downcase)
    end

    def isHQ?(room_id)
        room_id == @chatter.HQroom
    end

    def on?(room_id)
        isHQ?(room_id) || Room.on?(room_id)
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
end

def whoami(commander, room_id)
    return unless commander.on?(room_id)

    if commander.isHQ?(room_id) && rand(0...20) == rand(0...20)
        commander.chatter.say("24601")
    else
        commander.chatter.say("I go by #{commander.BOT_NAMES.join(" and ")}", room_id)
    end
end

def alive(commander, room_id, bot='*')
    return unless commander.matches_bot?(bot) || !commander.on?(room_id)
    commander.chatter.say("I'm alive and well :)", room_id)
end

def on(commander, room_id, bot='*')
    return unless commander.matches_bot?(bot)
    if Room.on?(room_id)
        commander.chatter.say("I'm already on, silly", room_id)
    else
        commander.chatter.say("Turning on...", room_id)
        Room.turn_on(room_id)
    end
end

def off(commander, room_id, bot='*')
    return unless commander.matches_bot?(bot)
    if !Room.on?(room_id)
        commander.chatter.say("I'm already off, silly", room_id)
    else
        commander.chatter.say("Turning off...", room_id)
        Room.turn_off(room_id)
    end
end

def mode(commander, room_id, bot='*')
    return unless commander.matches_bot?(bot) && commander.on?(room_id)
    if commander.isHQ?(room_id)
        commander.chatter.say("I'm in parent mode. I have children in rooms #{commander.chatter.rooms.flatten.map { |rid| "[#{rid}](https://chat.stackexchange.com/rooms/#{rid})"}.join(", ")}", room_id)
    else
        commander.chatter.say("I'm in child mode. My parent is in [room #{commander.chatter.HQroom}](https://chat.stackexchange.com/rooms/#{commander.chatter.HQroom})", room_id)
    end
end

def help(commander, room_id, bot='*')
    return unless commander.matches_bot?(bot) && commander.on?(room_id)
    if commander.isHQ?(room_id)
        commander.chatter.say(File.read('./hq_help.txt'), room_id)
    else
        commander.chatter.say(File.read("./help.txt"), room_id)
    end
end

def notify(commander, room_id, bot, type, status)
    return unless commander.matches_bot?(bot) && commander.on?(room_id)
    actions = { "regex" => :regex_match,
                 "magic" => :magic_comment}
    if !actions.key?(type)
        commander.chatter.say("Type must be one of {#{actions.keys.join(", ")}}")
        return
    end
    act = actions[type]

    if !["on", "off"].include? status
        commander.chatter.say("Status must be one of {on, off}")
        return
    end
    status = {"on" => true, "off" => false}[status]

    commander.chatter.say("I #{status ? "will" : "won't"} notify you on a #{act}", room_id) unless status.nil? || act.nil?
    Room.find_by(room_id: room_id).update(**{act => status}) unless status.nil? || act.nil?
end

def reports(commander, room_id, bot='*')
    return unless commander.matches_bot?(bot) && !commander.on?(room_id)
    room = Room.find_by(room_id: room_id)
    commander.chatter.say("regex_match: #{!!room.regex_match}\nmagic_comment: #{!!room.magic_comment}", room_id)
end

def whitelistuser(commander, room_id, bot, *uids)
    return unless commander.matches_bot?(bot)
    uids.each { |uid| WhitelistedUser.create(user_id: uid) }
    commander.chatter.say("Whitelisted users #{uids.join(', ')}", room_id)
end

def unwhitelistuser(commander, room_id, bot, *uids)
    return unless commander.matches_bot?(bot)
    uids.each { |uid| WhitelistedUser.where(user_id: uid).destroy_all }
    commander.chatter.say("Unwhitelisted users #{uids.join(', ')}", room_id)
end

def whitelisted(commander, room_id, bot='*')
    return unless commander.matches_bot?(bot)
    commander.chatter.say("Current whitelist: #{WhitelistedUser.all.map(&:user_id).join(', ')}", room_id)
end

def quota(commander, room_id, bot='*')
    return unless commander.matches_bot?(bot)
    commander.chatter.say "#{commander.seclient.quota} requests remaining"
end

def uptime(commander, room_id, bot='*')
    return unless commander.matches_bot?(bot)

    total_secs = (Time.now - commander.start_time).to_i
    secs = total_secs % 60; total_secs /= 60
    mins = total_secs % 60; total_secs /= 60
    hrs = total_secs % 24; total_secs /= 24
    days = total_secs

    commander.chatter.say("Up #{days} Days, #{hrs} hours, #{mins} minutes, #{secs} seconds", room_id)
end

def logsize(commander, room_id, bot='*')
    return unless commander.matches_bot?(bot)
    uncompressed = commander.to_sizes(Dir['*.log']+Dir['*.log.1']).map do |sizes|
        "#{sizes[:file]}: #{sizes[:size].round(2)}#{sizes[:ext]}"
    end
    compressed = {}
    commander.to_sizes(Dir['*.log*.gz']).each do |size|
        compressed[size[:file].split('.')[0]] ||= 0
        compressed[size[:file].split('.')[0]] += size[:size]
    end
    commander.chatter.say((uncompressed + compressed.map { |b, s| "#{b}: #{s.round(2)}MB" }).join("\n"), room_id)
end

def howmany(commander, room_id, bot='*')
    return unless commander.matches_bot?(bot)
    commander.chatter.say("I've scanned #{Comment.count} comments", room_id)
end

def test(commander, room_id, bot, type, *body)
    return unless commander.matches_bot?(bot)
    if !["q", "a"].include? type[0]
        commander.chatter.say("Type must be one of {q, a}", room_id)
        return
    end

    commander.chatter.say((commander.scanner.report(type, body.join(" ")) || "Didn't match any filters"), room_id)
end

def howgood(commander, room_id, bot, type, regex)
    return unless commander.matches_bot?(bot)
    puts type
    type = 'question' if type == 'q'
    type = 'answer' if type == 'a'
    unless ["question", "answer", "*"].include? type
         commander.chatter.say("Type must be one of {q, a, question, answer, *}", room_id)
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
        commander.percent_str(tps, total).center(14),
        commander.percent_str(tps, Comment.where("tps >= ?", 1).count).center(15),
        commander.percent_str(tps, Comment.count).center(18),
    ].join('|')

    fp_msg = [ # Generate fp line
        'fp'.center(6),
        fps.round(0).to_s.center(11),
        commander.percent_str(fps, total).center(14),
        commander.percent_str(fps, Comment.where("fps >= ?", 1).count).center(15),
        commander.percent_str(fps, Comment.count).center(18),
    ].join('|')

    total_msg = [ # Generate total line
        'Total'.center(6),
        total.round(0).to_s.center(11),
        '-'.center(14),
        '-'.center(15),
        commander.percent_str(total, Comment.count).center(18),
    ].join('|')

    # Generate header line
    header = " Type | # Matched | % of Matched | % of All Type | % of ALL Comments"

    final_output = [ # Add 4 spaces for formatting and newlines
        header, '-'*68, tp_msg, fp_msg, total_msg
    ].join("\n    ")
    msgs = MessageCollection::ALL_ROOMS
    msgs.push_howgood [regex, type], (commander.chatter.say("    #{final_output}", room_id))
end

def del(commander, room_id, bot, type, regex)
    return unless commander.matches_bot?(bot)
    if r = Regex.find_by(post_type: type[0], regex: regex)
        reas_id = r["reason_id"]
        commander.chatter.say("Destroyed #{r.regex} (post_type #{r.post_type})!", room_id) if r.destroy

        # If there are no other regexes for this reason, destroy the reason too
        if Regex.where(reason_id: reas_id).empty?
            reas = Reason.where(id: reas_id)[0]
            commander.chatter.say("Destroyed reason: \"#{reas["name"]}\"", room_id) if reas.destroy
        end
    else
        commander.chatter.say("Could not find regex to destroy", room_id)
    end

end

def add(commander, room_id, bot, type, regex, *reason)
    return unless commander.matches_bot?(bot)
    if !["q", "a"].include? type
        commands.chatter.say("Type must be one of {q, a}", room_id)
        return
    end

    begin
        %r{#{regex}}
    rescue RegexpError => e
        commander.chatter.say("Invalid regex: #{regex}", room_id)
        commander.chatter.say("    #{e}", room_id)
        return
    end

    if reason = Reason.find_or_create_by(name: reason.join(' '))
        if r = reason.regexes.create(post_type: type[0], regex: regex)
            commander.chatter.say("Added regex #{r.regex} for post_type #{r.post_type} with reason '#{r.reason.name}'", room_id)
        end
    end
end

def cid(commander, room_id, bot, *cids)
    return unless commander.matches_bot?(bot)
    commander.scanner.scan_comments_from_db(cids)
end

def pull(commander, room_id, bot='*', num_to_post=0, update_bundle=false)
    return unless commander.matches_bot?(bot)
    if `git symbolic-ref --short HEAD`.chomp != "master"
        commander.chatter.say("Pulling is only permitted when running on the master branch. Currently on #{`git rev-parse --abbrev-ref HEAD`.chop}.", room_id)
    else
        `git pull`
        commander.restart_bot(num_to_post, update_bundle)
    end
end

def master(commander, room_id, bot='*', *args)
    return unless commander.matches_bot?(bot)
    if `git symbolic-ref --short HEAD`.chomp == "master"
        commander.chatter.say("I'm already on master!", room_id)
    else
        `git checkout master`
        Kernel.exec("bundle exec ruby comment_scan.rb #{args.empty? ? @post_on_startup : args[0].to_i}")
    end
end

def restart(commander, room_id, bot='*', num_to_post=0, update_bundle=false)
    return unless commander.matches_bot?(bot)
    commander.restart_bot(num_to_post, update_bundle)
end

def kill(commander, room_id, bot='*')
    return unless commander.matches_bot?(bot)
    `kill -9 $(cat bot.pid)`
end

def rev(commander, room_id, bot='*')
    return unless commander.matches_bot?(bot)
    commander.chatter.say("Currently at rev #{`git rev-parse --short HEAD`.chop} on branch #{`git rev-parse --abbrev-ref HEAD`.chop}", room_id)
end

def manscan(commander, room_id, bot, *cids)
    return unless commander.matches_bot?(bot)
    commander.scanner.scan_comments(cids)
end

def ttscan(commander, room_id, bot='*')
    return unless commander.matches_bot?(bot)
    commander.chatter.say("#{commander.scanner.time_to_scan} seconds remaning until the next scan", room_id)
end

def last(commander, room_id, bot='*', num_comments="1")
    return unless commander.matches_bot?(bot)
    if !/\A\d+\z/.match(num_comments) || num_comments.to_i < 1
        commander.chatter.say("Bad number. Call last with `!!/last <bot> <num_comments>` where num_commments is >0", room_id)
    end

    commander.scanner.scan_last_n_comments(num_comments)
end

def regexes(commander, room_id, bot='*', reason=nil)
    return unless commander.matches_bot?(bot)
    reasons = (reason.nil? ? Reason.all : Reason.where("name LIKE ?", "%#{reason}%")).map do |r|
        regexes = r.regexes.map { |regex| "- #{regex.post_type}: #{regex.regex}" }
        "#{r.name.gsub(/\(\@(\w*)\)/, '(*\1)')}:\n#{regexes.join("\n")}"
    end
    reasonless_regexes = Regex.where(reason_id: nil).map { |regex| "- #{regex.post_type}: #{regex.regex}" }
    reasons << "Other Regexes:\n#{reasonless_regexes.join("\n")}"
    commander.chatter.say(reasons.join("\n"), room_id)
end

def regexstats(commander, room_id, bot='*', reason=nil)
    return unless commander.matches_bot?(bot)
    #Build array of hashes for each regex containing info to build the stat output
    regexes = (reason.nil? ? Reason.all : Reason.where("name LIKE ?", "%#{reason}%")).map do |r|
        r.regexes.map do |regex| 
            tps = Comment.where("tps >= ?", 1).count { |comment| %r{#{regex.regex}}.match(comment.body_markdown.downcase) }
            fps = Comment.where("fps >= ?", 1).count { |comment| %r{#{regex.regex}}.match(comment.body_markdown.downcase) }
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
    commander.chatter.say regexes.map { |r| 
        [
            "".ljust(4),
            commander.percent_str(r[:tps], r[:tps] + r[:fps],
                    precision: 1, blank_str: "n/a").ljust(percent_width),
            "(#{r[:tps]}/#{r[:tps] + r[:fps]})".ljust(tpfp_width),
            "| #{r[:regex]} (#{r[:postType]} - #{r[:reason]})"
        ].join
    }.join("\n"), room_id
end