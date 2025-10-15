require "websocket-client-simple"

class MediaStreamChannel < ApplicationCable::Channel
  SYSTEM_MESSAGE = "Eres un asistente espiritual compasivo y sabio que guía a las personas con mensajes inspiradores basados en la fe y la palabra de Dios. Ofreces consuelo, esperanza y sabiduría espiritual, citando pasajes bíblicos cuando sea apropiado. Mantienes un tono respetuoso, empático y reconfortante, siempre enfocándote en el amor de Dios y Su presencia en nuestras vidas. Respondes en español y adaptas tus mensajes para brindar paz y fortaleza espiritual. inicia saludando al usuario".freeze
  VOICE = "alloy".freeze
  LOG_EVENT_TYPES = [
    "error",
    "response.content.done",
    "rate_limits.updated",
    "response.done",
    "input_audio_buffer.committed",
    "input_audio_buffer.speech_stopped",
    "input_audio_buffer.speech_started",
    "session.created"
  ].freeze
  SHOW_TIMING_MATH = false

  def subscribed
    stream_from "media_stream"
    Rails.logger.info "Client connected to media stream"

    @stream_sid = nil
    @latest_media_timestamp = 0
    @last_assistant_item = nil
    @mark_queue = []
    @response_start_timestamp_twilio = nil

    connect_to_openai
  end

  def unsubscribed
    @openai_ws&.close
    Rails.logger.info "Client disconnected."
  end

  def receive(data)
    begin
      case data["event"]
      when "media"
        @latest_media_timestamp = data["media"]["timestamp"]
        Rails.logger.info "Received media message with timestamp: #{@latest_media_timestamp}ms" if SHOW_TIMING_MATH

        save_audio(data["media"]["payload"], @stream_sid) if data["media"]["payload"]
        append_audio_to_openai(data["media"]["payload"]) if @openai_ws&.open?
      when "start"
        @stream_sid = data["start"]["streamSid"]
        Rails.logger.info "Incoming stream has started: #{@stream_sid}"
        @response_start_timestamp_twilio = nil
        @latest_media_timestamp = 0
      when "mark"
        @mark_queue.shift if @mark_queue.any?
      else
        save_user_message(data["text"]) if data["text"]
        Rails.logger.info "Received non-media event: #{data['event']}"
      end
    rescue StandardError => e
      Rails.logger.error "Error parsing message: #{e.message}, Message: #{data.inspect}"
    end
  end

  private

  def connect_to_openai
    @openai_ws = WebSocket::Client::Simple.connect(
      "wss://api.openai.com/v1/realtime?model=gpt-4o-mini-realtime-preview-2024-12-17",
      headers: {
        "Authorization" => "Bearer #{Rails.application.credentials.openai_api_key}",
        "OpenAI-Beta" => "realtime=v1"
      }
    )

    @openai_ws.on :open do
      Rails.logger.info "Connected to the OpenAI Realtime API"
      initialize_session
    end

    @openai_ws.on :message do |msg|
      handle_openai_message(msg.data)
    end

    @openai_ws.on :close do
      Rails.logger.info "Disconnected from the OpenAI Realtime API"
    end

    @openai_ws.on :error do |e|
      Rails.logger.error "Error in the OpenAI WebSocket: #{e.message}"
    end
  end

  def initialize_session
    session_update = {
      type: "session.update",
      session: {
        turn_detection: { type: "server_vad" },
        input_audio_format: "g711_ulaw",
        output_audio_format: "g711_ulaw",
        voice: VOICE,
        instructions: SYSTEM_MESSAGE,
        modalities: [ "text", "audio" ],
        temperature: 0.8
      }
    }.to_json

    Rails.logger.info "Sending session update: #{session_update}"
    @openai_ws.send(session_update)
  end

  def handle_openai_message(data)
    response = JSON.parse(data)
    Rails.logger.info "Received event: #{response['type']}" if LOG_EVENT_TYPES.include?(response["type"])

    if response["type"] == "response.content.done" && response["content"]
      text = response["content"].select { |c| c["type"] == "text" }.map { |c| c["text"] }.join(" ")
      save_assistant_message(text) if text.present?
    end

    if response["type"] == "response.audio.delta" && response["delta"]
      audio_delta = {
        event: "media",
        streamSid: @stream_sid,
        media: { payload: response["delta"] }
      }.to_json
      ActionCable.server.broadcast("media_stream", audio_delta)
      save_audio(response["delta"], @stream_sid)

      @response_start_timestamp_twilio ||= @latest_media_timestamp
      Rails.logger.info "Setting start timestamp for new response: #{@response_start_timestamp_twilio}ms" if SHOW_TIMING_MATH

      @last_assistant_item = response["item_id"] if response["item_id"]
      send_mark
    end

    handle_speech_started_event if response["type"] == "input_audio_buffer.speech_started"
  rescue JSON::ParserError => e
    Rails.logger.error "Error processing OpenAI message: #{e.message}, Raw message: #{data}"
  end

  def handle_speech_started_event
    if @mark_queue.any? && @response_start_timestamp_twilio
      elapsed_time = @latest_media_timestamp - @response_start_timestamp_twilio
      Rails.logger.info "Calculating elapsed time for truncation: #{@latest_media_timestamp} - #{@response_start_timestamp_twilio} = #{elapsed_time}ms" if SHOW_TIMING_MATH

      if @last_assistant_item
        truncate_event = {
          type: "conversation.item.truncate",
          item_id: @last_assistant_item,
          content_index: 0,
          audio_end_ms: elapsed_time
        }.to_json
        Rails.logger.info "Sending truncation event: #{truncate_event}" if SHOW_TIMING_MATH
        @openai_ws.send(truncate_event)
      end

      ActionCable.server.broadcast("media_stream", { event: "clear", streamSid: @stream_sid }.to_json)
      @mark_queue = []
      @last_assistant_item = nil
      @response_start_timestamp_twilio = nil
    end
  end

  def send_mark
    return unless @stream_sid
    mark_event = { event: "mark", streamSid: @stream_sid, mark: { name: "responsePart" } }.to_json
    ActionCable.server.broadcast("media_stream", mark_event)
    @mark_queue << "responsePart"
  end

  def save_audio(payload, call_sid)
    return unless payload && call_sid
    audio_buffer = Base64.decode64(payload)
    File.open(Rails.root.join("tmp", "recording_#{call_sid}.raw"), "ab") { |f| f.write(audio_buffer) }
  rescue StandardError => e
    Rails.logger.error "Error saving audio: #{e.message}"
  end

  def save_assistant_message(text)
    File.open(Rails.root.join("tmp", "conversation_#{@stream_sid}.txt"), "a") { |f| f.puts("AI: #{text}") }
  rescue StandardError => e
    Rails.logger.error "Error saving assistant message: #{e.message}"
  end

  def save_user_message(text)
    File.open(Rails.root.join("tmp", "conversation_#{@stream_sid}.txt"), "a") { |f| f.puts("Usuario: #{text}") }
  rescue StandardError => e
    Rails.logger.error "Error saving user message: #{e.message}"
  end

  def append_audio_to_openai(payload)
    audio_append = { type: "input_audio_buffer.append", audio: payload }.to_json
    @openai_ws.send(audio_append)
  end
end
