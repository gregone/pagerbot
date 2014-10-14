# Hipchat webhook-using integration for pagerbot

require 'json'
require 'sinatra/base'
require 'rest-client'

module PagerBot
  class HipchatAdapter < Sinatra::Base
    def emoji
      configatron.bot.hipchat.emoji || "(pagey)"
    end

    def send_private_message(message, user_id)
      data = {
        username: configatron.bot.name,
        icon_emoji: emoji,
        text: message,
        channel: user_id,
        token: configatron.bot.hipchat.api_token
      }
      PagerBot.log.info(data.inspect)

      resp = RestClient.post "https://api.hipchat.com/v2/user/#{user_id}/message", data
      PagerBot.log.info resp
    end

    def make_reply(answer, event_data)
      if answer[:private_message]
        send_private_message(answer[:private_message], event_data[:user_id])
      end

      unless answer[:message]
        return ""
      end
      
      JSON.generate({
        username: configatron.bot.name,
        icon_emoji: emoji,
        text: answer[:message]
      })
    end

    def event_data(request)
      {
        token: request[:token],
        nick: request[:user_name],
        channel_name: request[:channel_name],
        text: request[:text],
        user_id: request[:user_id],
        adapter: :hipchat
      }
    end

    post '/' do
      PagerBot.log.info event_data(request)
      if configatron.bot.hipchat.webhook_token
        return "" unless request[:token] == configatron.bot.hipchat.webhook_token
      end
      return "" unless configatron.bot.channels.include? request[:channel_name]
      return "" unless request[:text].start_with?(configatron.bot.name+":")
      
      params = event_data request
      answer = PagerBot.process(params[:text], params)
      make_reply answer, params
    end

    get '/ping' do
      'pong'
    end
  end
end
