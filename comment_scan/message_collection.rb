class MessageCollection
  def initialize
    @messages = {}
    @howgoods = {}
  end
  
  def mytest()
    print "Message count is:" + @messages.keys.count.to_s
  end
  
  #TODO: Add some way to see what the regex was run on
  #       ie: q, a, *
  def push_howgood(regex_and_type, msg_ids)
    @howgoods[regex_and_type] ||= []
    @howgoods[regex_and_type].push(msg_ids)
    @howgoods[regex_and_type].flatten!
    if @howgoods.length > 10
      @howgoods.delete(@howgoods.keys.last)
    end
    @howgoods
  end
  
  def howgood_for(msg_id)
    m = @howgoods.select do |regex_and_type, msg_ids|
      msg_ids.include? msg_id
    end
    return nil if m.empty?
    m.first[0]
  end

  def push(comment, msg_ids)
    @messages[comment] ||= []
    @messages[comment].push(msg_ids)
    @messages[comment].flatten!
    if @messages.length > 200
      @messages.delete(@messages.keys.last)
    end
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
