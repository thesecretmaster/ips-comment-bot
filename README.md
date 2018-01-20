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

Either use environment variables with:

- Setup username with `export ChatXUsername='chat@bot.com'`
- Setup password with `export ChatXPassword='correct horse battery staple'`
- (OPTIONAL, but recommended) Setup API key with `expoert APIKey='jaoehoagheraghpreuihgape'`

Or you can create a `settings.yml` file with the form:

```yaml
ChatXUsername: chat@bot.com
ChatXPassword: 'correct horse battery staple'
APIKey: fajoweihfoaihfoiawhf
```

Run the bot (`bundle exec ruby comment_scan.rb`)

**Note:** if you get an error about login failing, you can check to make sure the `export` commands are working correctly by running `echo $ChatXUsername`, `echo $ChatXPassword` or `echo $APIKey`.
