# IPS Comment bot

## Installation

Prerequisites:

- Ruby version > 2.0.0 installed. (Check ruby version with `ruby --version`)
- Bundler installed (Check using `bundle --version`)

To install:

- Clone this repo (`git clone https://github.com/izwick-schachter/ips-comment-bot`)
- cd in to the directory (`cd ips-comment-bot`)
- Install dependencies (`bundle install`)
- Setup the database (`bundle exec rake db:setup`)

## Running the bot

Either use environment variables by setting all of the values in settings.sample.yml as environment variables (e.g. `export ChatXUsername='chat@bot.com'; export ChatXPassword='correct horse battery staple'` etc.) or you can create a `settings.yml` file based on settings.sample.yml

Run the bot (`bundle exec ruby comment_scan.rb`)

**Note:** if you get an error about login failing, you can check to make sure the `export` commands are working correctly by running `echo $ChatXUsername`, `echo $ChatXPassword` or `echo $APIKey`.
