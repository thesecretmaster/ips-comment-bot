require 'se/api'

class SEClient
    def initialize(apiKey, site)
        @site = site
        @client = SE::API::Client.new(apiKey, site: site)
    end

    def post_exists?(post_id)
        the_post = @client.posts(post_id.to_i)
        if the_post.empty?
            nil
        else
            the_post.first
        end
    end

    def comment_deleted?(comment_id)
        comment_with_id(comment_id) == nil
    end

    def comment_with_id(comment_id)
        client_response = @client.comments(comment_id)
        comment = client_response.empty? ? nil : client_response.first

        comment
    end

    def comments_after_date(date)
        @client.comments(fromdate: date)
    end

    def last_creation_date(num_to_ignore=0)
        comments = cli.comments[0..-1]
        comments[num_to_ignore].json["creation_date"].to_i+1 unless comments[num_to_ignore].nil?
    end

    def comments
        @client.comments
    end

    def latest_comment_date
        return nil if @client.comments[0].nil?
        @client.comments[0].json["creation_date"]
    end

    #TODO: For some reason this is always null...
    def quota
        @client.quota
    end
end