module ActivityBroker
  class FollowerRepository
    def initialize(logger)
      @logger = logger
      @followers = {}
    end

    def add_follower(follower: , followed:)
      @followers[followed] = fetch_followers(followed) << follower
    end

    def is_follower?(follower: , followed:)
      fetch_followers(followed).include?(follower)
    end

    def remove_follower(follower: , followed:)
      @followers[followed] = fetch_followers(followed) - [follower]
    end

    def following(followed)
      fetch_followers(followed)
    end

    private

    def fetch_followers(followed)
      @followers.fetch(followed, [])
    end
  end
end
