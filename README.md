# IPS Comment bot

## Installation

Prerequisites:

- Ruby version > 2.0.0 installed. (Check ruby version with `ruby --version`)
- Bundler installed (Check using `bundle --version`)

To install:

- Clone this repo (`git clone https://github.com/izwick-schachter/ips-comment-bot`)
- cd in to the directory (`cd ips-comment-bot`)
- Install dependencies (`bundle install`)

## Running the bot

Set up the environment:

- Setup username with `export ChatXUsername='chat@bot.com'`
- Setup password with `export ChatXPassword='correct horse battery staple'`
- (OPTIONAL, but recommended) Setup API key with `expoert APIKey='jaoehoagheraghpreuihgape'`

Run the bot (`bundle exec ruby comment_bot.rb`)

**Note:** if you get an error about login failing, you can check to make sure the `export` commands are working correctly by running `echo $ChatXUsername`, `echo $ChatXPassword` or `echo $APIKey`.
