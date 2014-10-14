module PagerBot; end

require 'logger'
require 'configatron'
# require_relative '../config'

require_relative './pagerbot/utilities'
require_relative './pagerbot/template'
require_relative './pagerbot/datastore'
require_relative './pagerbot/errors'
require_relative './pagerbot/pagerduty'
require_relative './pagerbot/parsing'
require_relative './pagerbot/action_manager'
require_relative './pagerbot/slack_adapter'
require_relative './pagerbot/hipchat_adapter'
require_relative './pagerbot/irc_adapter'
require_relative './pagerbot/plugin/plugin_manager'

module PagerBot
  def self.action_manager(config = nil)
    config ||= configatron.to_h
    @action_manager ||= PagerBot::ActionManager.new config
  end

  def self.plugin_manager
    action_manager.plugin_manager
  end

  def self.pagerduty
    action_manager.pagerduty
  end

  # Process the message, returning a string on what to respond and performs the
  # action indicated.
  def self.process(message, extra_info={})
    plugin_manager.load_plugins

    log.info "msg=#{message.inspect}, extra_info=#{extra_info.inspect}"
    query = PagerBot::Parsing.parse(message, configatron.bot.name)
    log.info "query=#{query.inspect}"
    answer = action_manager.dispatch(query, extra_info)
    log.info "answer=#{answer.inspect}"
    answer
  end

  def self.log
    return @logger unless @logger.nil?
    @logger = Logger.new STDERR
    @logger.level = Logger::INFO
    @logger.formatter = proc { |severity, datetime, progname, msg|
      "#{severity} #{caller[4]}: #{msg}\n"
    }
    @logger
  end

  # Load configuration saved into the database by AdminPage
  # into configatron, also adding schedules and users.
  # Dark magic lurks here!
  def self.load_configuration_from_db!
    store = DataStore.new
    settings = {}
    # load pagerduty settings
    settings[:pagerduty] = store.get_or_create('pagerduty')
    settings[:bot] = store.get_or_create('bot')
    settings[:plugins] = {}

    plugins = store.db_get_list_of('plugins')
    plugins.each do |plugin|
      next unless plugin[:enabled]
      settings[:plugins][plugin["name"]] = plugin["settings"]
    end

    puts settings
    settings[:pagerduty][:users] = store.db_get_list_of('users')
    settings[:pagerduty][:schedules] = store.db_get_list_of('schedules')
    configatron.configure_from_hash(settings)
  end

  def self.reload_configuration!
    @action_manager = nil
    # this will recreate the action_manager
    load_configuration_from_db!
    PagerBot.plugin_manager.load_plugins
    log.info("Reload configuration.\nNew configuration: #{configatron.to_h}")
  end
end

if __FILE__ == $0
  require_relative './admin/admin_server'
  def to_boolean(s)
    !!(s =~ /^(true|t|yes|y|1)$/i)
  end

  is_admin = ARGV.first.include? 'admin'
  is_admin ||= ARGV.first.include?('web') && !to_boolean(ENV['DEPLOYED'] || "")

  PagerBot.log.info("Is_admin is "+is_admin.to_s)
  if is_admin
    PagerBot::AdminPage.run!
  elsif ARGV.first.include?('slack') || ARGV.first.include?('web')
    PagerBot.reload_configuration!
    PagerBot::SlackAdapter.run!
  elsif ARGV.first.include?('hipchat') || ARGV.first.include?('web')
    PagerBot.reload_configuration!
    PagerBot::HipchatAdapter.run!
  elsif ARGV.first.include? 'irc'
    PagerBot.reload_configuration!
    PagerBot::IrcAdapter.run!
  else
    raise "Could not find adapter #{ARGV.first}. It must be either 'irc' or 'slack' or 'hipchat'"
  end
end
