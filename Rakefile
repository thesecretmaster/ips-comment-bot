load "active_record/railties/databases.rake"

seed_loader = Class.new do
  def load_seed
    load "#{ActiveRecord::Tasks::DatabaseTasks.db_dir}/seeds.rb"
  end
end

ActiveRecord::Tasks::DatabaseTasks.tap do |config|
  config.root                   = Rake.application.original_dir
  config.env                    = ENV["RACK_ENV"] || "development"
  config.db_dir                 = "db"
  config.migrations_paths       = ["db/migrate"]
  config.fixtures_path          = "test/fixtures"
  config.seed_loader            = seed_loader.new
  config.database_configuration = ActiveRecord::Base.configurations
end

# db:load_config can be overriden manually
Rake::Task["db:seed"].enhance(["db:load_config"])
Rake::Task["db:load_config"].clear

# define Rails' tasks as no-op
Rake::Task.define_task("db:environment")
Rake::Task["db:test:deprecated"].clear if Rake::Task.task_defined?("db:test:deprecated")

require "active_support/core_ext/string/strip"
require "pathname"
require "fileutils"

namespace :db do
  desc "Create a migration (parameters: NAME, VERSION)"
  task :create_migration do
    unless ENV["NAME"]
      puts "No NAME specified. Example usage: `rake db:create_migration NAME=create_users`"
      exit
    end

    name    = ENV["NAME"]
    version = ENV["VERSION"] || Time.now.utc.strftime("%Y%m%d%H%M%S")

    ActiveRecord::Migrator.migrations_paths.each do |directory|
      next unless File.exist?(directory)
      migration_files = Pathname(directory).children
      if duplicate = migration_files.find { |path| path.basename.to_s.include?(name) }
        puts "Another migration is already named \"#{name}\": #{duplicate}."
        exit
      end
    end

    filename = "#{version}_#{name}.rb"
    dirname  = ActiveRecord::Migrator.migrations_paths.first
    path     = File.join(dirname, filename)
    ar_maj   = ActiveRecord::VERSION::MAJOR
    ar_min   = ActiveRecord::VERSION::MINOR
    base     = "ActiveRecord::Migration"
    base    += "[#{ar_maj}.#{ar_min}]" if ar_maj >= 5

    FileUtils.mkdir_p(dirname)
    File.write path, <<-MIGRATION.strip_heredoc
      class #{name.camelize} < #{base}
        def change
        end
      end
    MIGRATION

    puts path
  end
end

# The `db:create` and `db:drop` command won't work with a DATABASE_URL because
# the `db:load_config` command tries to connect to the DATABASE_URL, which either
# doesn't exist or isn't able to drop the database. Ignore loading the configs for
# these tasks if a `DATABASE_URL` is present.
if ENV.has_key? "DATABASE_URL"
  Rake::Task["db:create"].prerequisites.delete("load_config")
  Rake::Task["db:drop"].prerequisites.delete("load_config")
end

ActiveRecord::Base.logger = nil

namespace :db do
  task :load_config do
    require "./db"
    setup_db("db/db.sqlite3")
  end
end
