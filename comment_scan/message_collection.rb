class MessageCollection
  def initialize
    @messages = {}
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
