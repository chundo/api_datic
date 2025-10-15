# frozen_string_literal: true

class HomeChannel < ApplicationCable::Channel
  def subscribed
    # { "command": "subscribe",  "identifier": "{\"channel\": \"HomeChannel\", \"room\": \"chundo\" }" }
    Rails.logger.debug '--- Conection ok -----'
    room = params['room'] || params[:room]
    stream_from "chat_#{room}"
    data = { message: 'Conection ok' }
    ## code and data
    ActionCable.server.broadcast("chat_#{room}", data)
  end

  def unsubscribed
    # { "command": "unsubscribe", "identifier":  "{\"channel\": \"HomeChannel\", \"room\": \"chundo\" }" }
    Rails.logger.debug '--- Conection off -----'
  end

  def receive(data)
    # { "command": "message",  "identifier": "{\"channel\": \"HomeChannel\", \"room\": \"chundo\" }", "data": "{\"channel\": \"HomeChannel\", \"room\": \"chundo\" }" }
    Rails.logger.debug '--- Data  received -----'
    ## code and data
    ActionCable.server.broadcast("chat_#{params[:room]}", data)
  end
end
