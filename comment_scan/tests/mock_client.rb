require 'date'

class MockClient
    attr_reader :posts

    def initialize()
        @comments = Hash.new()
        @posts = Hash.new()
        @users = Hash.new()
        @last_creation_date = Date.new(2000,1,1).to_time #Make things easy...go back to a simpler time
        @last_id = 1
    end

    #alias--the real client gives an array of comments like this
    def comments
        @comments.values
    end

    def post_exists?(post_id)
        @posts[post_id] #Will be nil if we don't have it
    end 

    def comment_deleted?(comment_id)
        !@comments.key?(comment_id)
    end

    def comments_after_date(date)
        @comments.select { |id, comment| date.nil? || comment.json["creation_date"] > date }.values
    end

    def last_creation_date(num_to_ignore=0)
        comments.values[num_to_ignore].json["creation_date"].to_i+1 unless comments.values[num_to_ignore].nil?
    end

    def latest_comment_date
        return nil unless @comments.any?
        @comments[@comments.keys.max].creation_date
    end

    def new_comment(post_type, body)
        @last_creation_date += 1 #Newer!

        biggest_post = @posts.any? ? @posts.keys.max : 0
        biggest_user = @users.any? ? @users.keys.max : 0
        biggest_comment = @comments.any? ? @comments.keys.max : 0

        comment_owner = new_user(biggest_user + 1)
        post_owner = new_user(biggest_user + 2)
        last_editor = new_user(biggest_user + 3)

        parent_post = new_post(biggest_post + 1, Date.new(2000, 1, 1).to_time, post_type, post_owner, last_editor)

        @comments[biggest_comment + 1] = MockComment.new(biggest_comment + 1, @last_creation_date, parent_post.id, post_type, body, comment_owner)

        return @comments[biggest_comment + 1]
    end

    def new_user(id)
      @users[id] = MockUser.new(id)
      @users[id]
    end

    def new_post(id, creation_date, post_type, owner, editor)
      @posts[id] = MockPost.new(id, creation_date, post_type, owner, editor)
      @posts[id]
    end

    def delete_comment(id)
        @comments.delete(id)
    end

    class MockComment
        attr_reader :id, :creation_date, :body, :edited, :link, :post_id, :post_type, :score, :owner

        def initialize(id, creation_date, post_id, post_type, body, owner)
            @id = id
            @creation_date = creation_date
            @body = body
            @post_id = post_id
            @post_type = post_type #Either "question" or "answer"
            @link = "https://interpersonal.stackexchange.com/q/#{post_id}/#comment#{id}" #build a mock (working) link
            @edited = false #Never used, so just say no
            @score = 0 #Never used so just so 0

            @owner = owner
        end

        #alias for body
        def body_markdown
            @body
        end

        #alias for id
        def comment_id
            @id
        end

        #For some reason, we do .json to grab this...idk man.
        def json
            {"creation_date" => @creation_date}
        end
    end

    class MockUser
        attr_reader :id, :name, :reputation, :link, :type

        def initialize(id)
            @id = id
            @name = "Mock User #{id}"
            @reputation = id.to_i * 100
            @type = 'registered' #Unused, so make it easy
            @link = "https://interpersonal.stackexchange.com/user/#{id}/person"
        end
    end

    class MockPost
        attr_reader :id, :owner, :last_editor, :creation_date, :last_edit_date, :type, :closed_date, :title, :link, :score, :comments

        def initialize(id, creation_date, type, owner, last_editor)
            @id = id
            @creation_date = creation_date
            @last_edit_date = creation_date
            @last_activity_date = creation_date
            @type = type
            @owner = owner 
            @last_editor = last_editor
            @closed_date = nil
            @comments = [] #Only used for magic comment. This makes things easy
        end

        def json
            {"creation_date" => @creation_date, "last_edit_date" => @last_edit_date, 
                "closed_date" => @closed_date, "last_activity_date" => @last_activity_date}
        end

    end


end
