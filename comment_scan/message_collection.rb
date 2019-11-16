class MessageCollection
  def initialize
    self.clear
  end

  def clear #Clear/reset everything
    @messages = Hash.new { |hash, key| hash[key] = [] } #Automagically create an array for each new key
    @howgoods = {}
    @hotposts = []
  end

  def push_hot_post(post_id)
    @hotposts.push(post_id)
    @hotposts.shift if @hotposts.length > 10 #remove first hot_post
    @hotposts
  end

  def hot_post_recorded?(post_id)
    @hotposts.include?(post_id)
  end
  
  def push_howgood(regex_and_type, msg_id)
    @howgoods[msg_id] = regex_and_type
    @howgoods.delete(@howgoods.keys.last) if @howgoods.length > 10
    @howgoods
  end
  
  def howgood_for(msg_id)
    @howgoods[msg_id]
  end

  def push(comment, msg_ids)
    @messages[comment].push(*msg_ids)
    @messages.delete(@messages.keys.last) if @messages.length > 200
    @messages
  end

  def comment_for(msg_id)
    m = @messages.select do |comment, msg_ids|
      msg_ids.include? msg_id
    end
    return nil if m.empty?
    m.first[0]
  end

  def msg_ids_for(comment)
    @messages[comment].flatten
  end

  alias_method :message_ids_for, :msg_ids_for

  def swap_key(key, nkey)
    @messages[nkey] = @messages.delete(key)
  end

  def logger
    self.class.logger
  end

  class << self
    def logger
      @logger ||= Logger.new('ips_debug.log')
    end
  end

  ALL_ROOMS = self.new
end
