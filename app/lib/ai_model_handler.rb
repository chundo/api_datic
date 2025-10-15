# frozen_string_literal: true

class AiModelHandler
  MODEL_REGISTRY = {
    "openai" => :call_openai,
    "claude" => :call_claude,
    "deepseek" => :call_deepseek,
    "digitalocean" => :call_digital_ocean,
    "grok" => :call_grok,
    "gemini" => :call_gemini,
    "function" => :call_function,
    "whisper" => :call_whisper,
    "mcp" => :call_openai_mcp,
    "local" => :call_local,
    "local_mcp" => :call_local_mcp
  }.freeze

  def initialize(api_keys = {})
    @openai_key = api_keys[:openai] || ENV.fetch("OPEN_AI_TOKEN", nil)
    @aws_config = {
      access_key_id: api_keys[:aws_access_key] || ENV.fetch("AWS_ACCESS_KEY_ID", nil),
      secret_access_key: api_keys[:aws_secret_key] || ENV.fetch("AWS_SECRET_ACCESS_KEY", nil),
      region: api_keys[:aws_region] || ENV["AWS_REGION"] || "us-east-1"
    }
    @deep_seek_key = api_keys[:deep_seek_key] || ENV.fetch("DEEPSEEK", nil)
    @deep_seek_url = Settings.deep_seek_url
    @deep_seek_dg_url = Settings.deep_seek_dg_url
    @grock_url = Settings.grock_url
    @deep_seek_dg_key = api_keys[:deep_seek_dg_key] || ENV.fetch("DO_KEY_AI", nil)
    @grock_key = api_keys[:grok] || ENV.fetch("GROK", nil)
    @gemini_url = Settings.gemini_url
    @gemini_key = api_keys[:grok] || ENV.fetch("GEMINI_TOKEN", nil)
    @local_url = Settings.local_url
  end

  def generate(prompt_params:, model: "deepseek", model_version: nil, attachments: nil, temperature: 0.7,
               max_tokens: 4000, tools: nil)
    full_prompt = build_prompt(prompt: prompt_params, attachments: attachments)

    return { error: "Modelo no soportado", available_models: MODEL_REGISTRY.keys } unless MODEL_REGISTRY.key?(model)

    model_version ||= default_model_for(model: model)
    send(MODEL_REGISTRY[model], full_prompt: full_prompt, model_version: model_version, attachments: attachments,
                                temperature: temperature, max_tokens: max_tokens, tools: tools)
  rescue StandardError => e
    { error: "Error en generación: #{e.message}", model: model }
  end

  private

  def build_prompt(prompt:, attachments:)
    return prompt.dup if prompt.is_a?(String)

    base_prompt = prompt[:promp]

    components = []
    components << "data: #{prompt[:data]}" if prompt[:data]

    "#{base_prompt}\n\n#{components.join("\n")}".strip
  end

  # Nueva función para procesar attachments según el modelo
  def process_attachments_for_model(attachments:, model:)
    return [] if attachments.blank?

    attachments = Array(attachments)
    content = []

    attachments.each do |attachment|
      processed = process_attachment(attachment: attachment)
      next unless processed[:success]

      # Determinar el tipo MIME del archivo
      mime_type = determine_mime_type(attachment: attachment)

      case model
      when "whisper"
        # Para whisper, necesitamos el archivo directamente (no una URL)
        # Retornamos el archivo procesado para que `call_whisper` lo use
        content << { type: "file", file: attachment, processed: processed }
      else
        # Para otros modelos (openai, grok, gemini, deepseek), asumimos que pueden manejar imágenes
        if mime_type&.start_with?("image/")
          content << { type: "image_url", image_url: { url: processed[:url] } }
        else
          Rails.logger.warn "Tipo de archivo no soportado para el modelo #{model}: #{mime_type}"
          content << { type: "text", text: "[Archivo no soportado: #{processed[:url]}]" }
        end
      end
    end

    content
  end

  def determine_mime_type(attachment:)
    if attachment.is_a?(ActionDispatch::Http::UploadedFile)
      attachment.content_type
    elsif attachment.is_a?(String) && File.exist?(attachment)
      MimeMagic.by_path(attachment)&.type
    elsif attachment.is_a?(String) && valid_url?(attachment)
      # Para URLs, intentamos inferir el tipo MIME (esto puede requerir una solicitud HEAD en un caso real)
      ext = File.extname(URI.parse(attachment).path)
      MimeMagic.by_extension(ext)&.type
    else
      nil
    end
  end

  def call_local(full_prompt:, model_version:, attachments:, temperature:, max_tokens:, tools:)
    # client = OpenAI::Client.new(access_token: @openai_key)
    client = OpenAI::Client.new(base_url: @local_url, api_key: 'aa')

    content = [ { type: "text", text: full_prompt } ]
    additional_content = process_attachments_for_model(attachments: attachments, model: "openai/gpt-oss-20b")
    content.concat(additional_content)

    message = [ { role: "user", content: content } ]

    # response = client.chat(
    response = client.chat.completions.create(
      # parameters: {
      model: model_version,
      messages: message,
      temperature: temperature,
      max_tokens: max_tokens
      # }
    )

    process_openai_response(response: response, model_version: model_version)
  end

  def call_local_mcp(full_prompt:, model_version:, attachments:, temperature:, max_tokens:, tools:)
    client = OpenAI::Client.new(base_url: @local_url)

    response = client.responses.create(
      # id: 'chatcmpl-BzAV84Du3aKyeUFmnF39expu7qN4u',
      model: model_version,
      tools: tools,
      input: full_prompt
    )

    process_mcp_response(response: response, model_version: model_version)
  end

  def call_openai(full_prompt:, model_version:, attachments:, temperature:, max_tokens:, tools:)
    # client = OpenAI::Client.new(access_token: @openai_key)
    client = OpenAI::Client.new(api_key: @openai_key)

    content = [ { type: "text", text: full_prompt } ]
    additional_content = process_attachments_for_model(attachments: attachments, model: "openai")
    content.concat(additional_content)

    message = [ { role: "user", content: content } ]

    # response = client.chat(
    response = client.chat.completions.create(
      # parameters: {
      model: model_version,
      messages: message,
      temperature: temperature,
      max_tokens: max_tokens
      # }
    )

    process_openai_response(response: response, model_version: model_version)
  end

  def call_openai_mcp(full_prompt:, model_version:, attachments:, temperature:, max_tokens:, tools:)
    client = OpenAI::Client.new(api_key: @openai_key)
    token_stripe = ENV.fetch("STRIPE_SK", nil)

    tool = [
      {
        type: "mcp",
        server_label: "deepwiki",
        server_url: "https://mcp.deepwiki.com/mcp",
        require_approval: "never"
      },
      {
        type: "mcp",
        server_label: "stripe",
        server_url: "https://mcp.stripe.com",
        server_description: "Server",
        headers: {
          Authorization: "Bearer #{token_stripe}"
        }
      }
    ]

    response = client.responses.create(
      # id: 'chatcmpl-BzAV84Du3aKyeUFmnF39expu7qN4u',
      model: "gpt-4.1",
      tools: tool,
      input: full_prompt
    )

    process_openai_response(response: response, model_version: model_version)
  end

  def call_whisper(full_prompt:, model_version:, attachments:, temperature:, max_tokens:)
    client = OpenAI::Client.new(access_token: @openai_key)

    # Procesar attachments para whisper
    processed_attachments = process_attachments_for_model(attachments: attachments, model: "whisper")

    # Whisper solo puede procesar un archivo de audio a la vez
    attachment = processed_attachments.find { |item| item[:type] == "file" }
    return { error: "No se proporcion\u00F3 un archivo de audio v\u00E1lido para Whisper" } unless attachment

    file = if attachment[:file].is_a?(ActionDispatch::Http::UploadedFile)
             File.open(attachment[:file].tempfile, "rb")
    elsif attachment[:file].is_a?(String) && File.exist?(attachment[:file])
             File.open(attachment[:file], "rb")
    else
             return { error: "Archivo no válido para Whisper: #{attachment[:file]}" }
    end

    begin
      response = client.audio.transcribe(
        parameters: {
          model: model_version,
          file: file
        }
      )
      { success: true, response: response["text"], model: model_version }
    rescue StandardError => e
      { error: "Error en transcripción con Whisper: #{e.message}", model: model_version }
    ensure
      file&.close
    end
  end

  def call_grok(full_prompt:, model_version:, attachments:, temperature:, max_tokens:, tools: nil)
    # client = OpenAI::Client.new(access_token: @grock_key, uri_base: @grock_url)
    client = OpenAI::Client.new(api_key: @grock_key, base_url: @grock_url)

    content = [ { type: "text", text: full_prompt } ]
    additional_content = process_attachments_for_model(attachments: attachments, model: "grok")
    content.concat(additional_content)

    message = [ { role: "user", content: content } ]

    response = client.chat.completions.create(
      model: model_version,
      messages: message,
      temperature: temperature,
      max_tokens: max_tokens
    )
    process_grok_response(response: response, model_version: model_version)
  end

  def call_gemini(full_prompt:, model_version:, attachments:, temperature:, max_tokens:, tools: nil)
    # client = OpenAI::Client.new(access_token: @gemini_key, uri_base: @gemini_url)
    client = OpenAI::Client.new(api_key: @gemini_key, base_url: @gemini_url)

    content = [ { type: "text", text: full_prompt } ]
    additional_content = process_attachments_for_model(attachments: attachments, model: "gemini")
    content.concat(additional_content)

    message = [ { role: "user", content: content } ]

    response = client.chat.completions.create(
      model: model_version,
      messages: message,
      temperature: temperature,
      max_tokens: max_tokens
    )
    process_grok_response(response: response, model_version: model_version)
  end

  def call_deepseek(full_prompt:, model_version:, attachments:, temperature:, max_tokens:, tools: nil)
    # client = OpenAI::Client.new(access_token: @deep_seek_key, uri_base: @deep_seek_url)
    client = OpenAI::Client.new(api_key: @deep_seek_key, base_url: @deep_seek_url)

    content = [ { type: "text", text: full_prompt } ]
    additional_content = process_attachments_for_model(attachments: attachments, model: "deepseek")
    content.concat(additional_content)

    message = [ { role: "user", content: content } ]

    response = client.chat.completions.create(
      model: model_version,
      messages: message,
      temperature: temperature,
      max_tokens: max_tokens
    )

    process_deepseek_response(response: response, model_version: model_version)
  end

  def call_digital_ocean(full_prompt:, model_version:, attachments:, temperature:, max_tokens:, tools: nil)
    client = OpenAI::Client.new(access_token: @deep_seek_dg_key, uri_base: @deep_seek_dg_url)

    message = [ { role: "user", content: full_prompt } ]

    response = client.chat(
      parameters: {
        model: model_version,
        messages: message
      }
    )
    process_grok_response(response: response, model_version: model_version)
  end

  def call_claude(full_prompt:, model_version:, attachments:, temperature:, max_tokens:, tools: nil)
    bedrock = Aws::BedrockRuntime::Client.new(@aws_config)

    content = [ { text: full_prompt } ]
    # TODO: Si Claude necesita manejar attachments, podemos usar process_attachments_for_model aquí
    message = [ { role: "user", content: content } ]

    response = bedrock.converse({
                                  model_id: model_version,
                                  messages: message,
                                  inference_config: {
                                    temperature: temperature,
                                    max_tokens: max_tokens
                                  }
                                })

    process_bedrock_response(response: response, model_version: model_version)
  end

  def call_function(full_prompt:, model_version:, attachments:, temperature: 0.7, max_tokens: 1000)
    client = OpenAI::Client.new(access_token: @openai_key)
    messages = [ { role: "user", content: full_prompt } ]
    tools = [ {
      type: "function",
      function: {
        name: "get_weather",
        description: "Get current temperature for a given location.",
        parameters: {
          type: "object",
          properties: {
            location: {
              type: "string",
              description: "City and country e.g. Bogot\u00E1, Colombia"
            },
            latitude: {
              type: "string",
              description: "3.43722"
            },
            longitude: {
              type: "string",
              description: "-76.5225"
            }
          },
          required: %w[
            location
            latitude
            longitude
          ]
        }
      }
    } ]

    response = client.chat(
      parameters: {
        model: model_version,
        messages: messages,
        tools: tools
      }
    )

    process_function_response(response: response, model_version: model_version, tools: tools)
  rescue StandardError => e
    { error: "Error en función: #{e.message}", backtrace: e.backtrace }
  end

  def process_openai_response(response:, model_version:)
    # byebug

    {
      success: true,
      id: response[:id] || response["id"],
      response: response[:choices][0][:message][:content] || response.dig("choices", 0, "message", "content"),
      # response: response
      model: model_version,
      metadata: {
        tokens_used: response[:usage][:total_tokens] || response.dig("usage", "total_tokens"),
        finish_reason: response[:choices][0][:finish_reason] || response.dig("choices", 0, "finish_reason")
      }
    }
  end

  def process_mcp_response(response:, model_version:)
    # byebug

    {
      success: true,
      # id: response[:id] || response['id'],
      response: response[:output][0][:content][0][:text] || response.dig("output", 0, "content", 0, "text"),
      # response: response
      model: model_version,
      metadata: {
        tokens_used: response[:usage][:total_tokens] || response.dig("usage", "total_tokens"),
        finish_reason: response[:choices][0][:finish_reason] || response.dig("choices", 0, "finish_reason")
      }
    }
  end

  def process_grok_response(response:, model_version:)
    # byebug

    {
      success: true,
      # response: response
      response: response[:choices][0][:message][:content] || response.dig("choices", 0, "message", "content")
      # model: model_version,
      # metadata: {
      #   tokens_used: response.dig('usage', 'total_tokens'),
      #   finish_reason: response.dig('choices', 0, 'finish_reason')
      # }
    }
  end

  def process_deepseek_response(response:, model_version:)
    {
      success: true,
      # response: response[:choices][0][:message][:content] || response.dig('choices', 0, 'message', 'content'),
      response: response,
      model: model_version,
      metadata: {
        # tokens_used: response[:usage][:total_token] || response.dig('usage', 'total_tokens'),
        # finish_reason: response[:choices][0][:finish_reason] || response.dig('choices', 0, 'finish_reason')
      }
    }
  end

  def process_bedrock_response(response:, model_version:)
    {
      success: true,
      response: response.output.message.content.first.text,
      model: model_version,
      metadata: {
        stop_reason: response.stop_reason,
        token_count: response.usage.total_tokens
      }
    }
  end

  def process_function_response(response:, model_version:, tools:)
    tool_call = response.dig("choices", 0, "message", "tool_calls", 0)
    args = tool_call["function"]
    data = JSON.parse(args["arguments"])
    send(args["name"], data)
  end

  def default_model_for(model:)
    case model
    when "openai" then "gpt-4.1-nano"
    when "claude" then "anthropic.claude-3-sonnet-20240229-v1:0"
    when "deepseek" then "deepseek-chat"
    when "digitalocean" then "n/a"
    when "grok" then "grok-2-1212"
    when "gemini" then "gemini-2.5"
    when "function" then "o1"
    when "whisper" then "whisper-1"
    when "mcp" then "gpt-4.1"
    when "local" then "gpt-oss-20b"
    when "local_mcp" then "gpt-oss-20b"
    else "unknown"
    end
  end

  def get_weather(params)
    latitude = params["latitude"].to_f
    longitude = params["longitude"].to_f
    response = HTTParty.get("https://api.open-meteo.com/v1/forecast?latitude=#{latitude}&longitude=#{longitude}¤t=temperature_2m,wind_speed_10m&hourly=temperature_2m,relative_humidity_2m,wind_speed_10m")
    data = response.parsed_response
    data.dig("current", "temperature_2m")
  end

  def process_attachment(attachment:)
    return { success: true, url: attachment } if attachment.is_a?(String) && valid_url?(attachment)

    return handle_uploaded_file(file: attachment) if attachment.is_a?(ActionDispatch::Http::UploadedFile)

    return handle_local_file(file_path: attachment) if attachment.is_a?(String) && File.exist?(attachment)

    { success: false, error: "Formato de attachment no válido: #{attachment.class}" }
  end

  def handle_uploaded_file(file:)
    Rails.logger.info "Procesando archivo subido: #{file.original_filename}"

    begin
      blob = ActiveStorage::Blob.create_and_upload!(
        io: file.tempfile,
        filename: file.original_filename,
        content_type: file.content_type
      )

      temp_url = Rails.application.routes.url_helpers.rails_blob_url(
        blob,
        disposition: "inline",
        expires_in: 5.minutes,
        only_path: false
      )

      { success: true, url: temp_url }
    rescue StandardError => e
      Rails.logger.error "Error al procesar archivo subido: #{e.message}"
      { success: false, error: "Error al procesar archivo: #{e.message}" }
    end
  end

  def handle_local_file(file_path:)
    Rails.logger.info "Procesando archivo local: #{file_path}"

    begin
      return { success: false, error: "Archivo no encontrado" } unless File.exist?(file_path)
      return { success: false, error: "El path no es un archivo" } unless File.file?(file_path)

      file_content = File.open(file_path, "rb")
      blob = ActiveStorage::Blob.create_and_upload!(
        io: file_content,
        filename: File.basename(file_path),
        content_type: MimeMagic.by_path(file_path)&.type || "application/octet-stream"
      )

      temp_url = Rails.application.routes.url_helpers.rails_blob_url(
        blob,
        disposition: "inline",
        expires_in: 5.minutes,
        host: Settings.localhost,
        only_path: true
      )

      { success: true, url: temp_url }
    rescue StandardError => e
      Rails.logger.error "Error al procesar archivo local: #{e.message}"
      { success: false, error: "Error al procesar archivo: #{e.message}" }
    ensure
      file_content&.close
    end
  end
end
