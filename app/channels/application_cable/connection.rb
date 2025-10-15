# frozen_string_literal: true

module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :connection_identifier

    def connect
      # For Twilio connections, we're not doing authentication
      # but we still need a unique identifier for the connection
      self.connection_identifier = SecureRandom.uuid
      Rails.logger.info "WebSocket connected with ID: #{connection_identifier}"
    end

    def disconnect
      Rails.logger.info "WebSocket disconnected ID: #{connection_identifier}"
    end
  end
end
