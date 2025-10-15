# frozen_string_literal: true

require "net/http"
require "json"
require "openai"
require "open-uri"

class OpenAi
  API_BASE_URL = "https://api.openai.com/v1"
  MODEL_NAME = "gpt-3.5-turbo-0125"
  MAX_TOKENS = 2000

  def self.models
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))

    client.models.list
  end

  def self.code(messages, model_name = MODEL_NAME, _attachments = nil)
    data = {
      model: model_name,
      # response_format: { type: 'json_object' },
      messages:
      #  temperature: 1,
      #  seed: 1
    }

    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))

    response = client.chat(parameters: data)

    response.dig("choices", 0, "message", "content")
  end

  def self.completions(answer, model_name = MODEL_NAME, attachments = nil)
    if attachments.present?
      menssages_qs = []
      if attachments.instance_of?(Array) && attachments.length > 1
        attachments.each_with_index do |attachment, _index|
          menssages_qs.push({
                              type: "image_url",
                              image_url: {
                                url: attachment
                              }
                            })
        end
        menssages_qs.push({ type: "text", text: answer })

        data = {
          model: model_name,
          max_tokens: MAX_TOKENS,
          messages: [ { role: "user", content: menssages_qs } ]
        }
      else
        data = {
          model: model_name,
          messages: [
            {
              role: "user",
              content: [
                {
                  type: "text",
                  text: answer
                },
                {
                  type: "image_url",
                  image_url: {
                    url: attachments[0]
                  }
                }
              ]
            }
          ],
          max_tokens: MAX_TOKENS
        }
      end
    else
      data = {
        model: model_name,
        messages: [
          { role: "user", content: answer }
        ]
      }
    end

    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))

    response = client.chat(parameters: data)

    response.dig("choices", 0, "message", "content")
    # make_request(api_url, data)
  end

  def self.assistants
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))

    client.assistants.list["data"]
  end

  def self.assistants_v2
    url = URI("#{API_BASE_URL}/assistants?order=desc&limit=50")

    http = Net::HTTP.new(url.host, url.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(url)
    request["Content-Type"] = "application/json"
    request["Authorization"] = "Bearer #{ENV.fetch('OPEN_AI_TOKEN', nil)}"
    request["OpenAI-Beta"] = "assistants=v2"

    response = http.request(request)

    handle_response(response)
  end

  def self.assistant_create(name, instructions, model_name = MODEL_NAME)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))

    data = {
      instructions:,
      # description: "A simple assistant for testing purposes.",
      name:,
      tools: [ { type: "code_interpreter" } ],
      model: model_name,
      metadata: { user_email: Settings.default_user_email }
    }

    client.assistants.create(parameters: data)
  end

  def self.assistant(id)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))

    client.assistants.retrieve(id:)
  end

  def self.assistant_file_up(assistant_id, file_id)
    api_url = URI.parse("#{API_BASE_URL}/assistants/#{assistant_id}/files")

    http = Net::HTTP.new(api_url.host, api_url.port)
    http.use_ssl = true

    headers = {
      "Authorization" => "Bearer #{ENV.fetch('OPEN_AI_TOKEN', nil)}",
      "Content-Type" => "application/json",
      "OpenAI-Beta" => "assistants=v2"
    }
    data = { file_id: }

    request = Net::HTTP::Post.new(api_url.path, headers)
    request.body = data.to_json

    response = http.request(request)

    handle_response(response)
  end

  def self.assistant_files(id)
    api_url = URI.parse("#{API_BASE_URL}/assistants/#{id}/files")

    http = Net::HTTP.new(api_url.host, api_url.port)
    http.use_ssl = true

    headers = {
      "Authorization" => "Bearer #{ENV.fetch('OPEN_AI_TOKEN', nil)}",
      "Content-Type" => "application/json",
      "OpenAI-Beta" => "assistants=v2"
    }

    request = Net::HTTP::Get.new(api_url.path, headers)
    # request.body = data.to_json

    response = http.request(request)

    handle_response(response)
  end

  def self.assistant_delete(id)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))

    client.assistants.delete(id:)
  end

  def self.assistant_file_delete(assistant_id, file_id)
    api_url = URI.parse("#{API_BASE_URL}/assistants/#{assistant_id}/files/#{file_id}")

    request = Net::HTTP::Delete.new(api_url)
    request["Authorization"] = "Bearer #{ENV.fetch('OPEN_AI_TOKEN', nil)}"
    request["Content-Type"] = "application/json"
    request["OpenAI-Beta"] = "assistants=v2"

    # Enviar la solicitud y verificar la respuesta
    response = Net::HTTP.start(api_url.hostname, api_url.port, use_ssl: api_url.scheme == "https") do |http|
      http.request(request)
    end
    handle_response(response)
  end

  def self.assistant_download_file(file_id)
    api_url = URI.parse("#{API_BASE_URL}/files/#{file_id}/content")

    http = Net::HTTP.new(api_url.host, api_url.port)
    http.use_ssl = true

    headers = {
      "Authorization" => "Bearer #{ENV.fetch('OPEN_AI_TOKEN', nil)}",
      "Content-Type" => "application/json",
      "OpenAI-Beta" => "assistants=v2"
    }

    request = Net::HTTP::Get.new(api_url.path, headers)

    response = http.request(request)
    file = file(file_id)
    file_name = file["filename"].split("/")[-1]

    File.binwrite(file_name, response.body)
  end

  ## Threads
  def self.create_thread(data = {})
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))
    client.threads.create(parameters: data)
  end

  def self.thread(thread_id)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))

    client.threads.retrieve(id: thread_id)
  end

  def self.modify_thread(thread_id, data)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))

    data = {
      metadata: data
    }
    client.threads.modify(id: thread_id, parameters: data)
  end

  def self.delete_thread(thread_id)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))

    client.threads.delete(id: thread_id)
  end

  ## Messages
  def self.create_message(thread_id, menssage, files = [])
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))
    data = {
      role: "user",
      content: menssage,
      file_ids: files
    }
    client.messages.create(thread_id:, parameters: data)
  end

  def self.thread_messages(thread_id)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))

    client.messages.list(thread_id:)
  end

  def self.thread_message(thread_id, msg_id)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))

    client.messages.retrieve(thread_id:, id: msg_id)
  end

  def self.thread_message_files(thread_id, msg_id)
    api_url = URI.parse("#{API_BASE_URL}/threads/#{thread_id}/messages/#{msg_id}/files")

    http = Net::HTTP.new(api_url.host, api_url.port)
    http.use_ssl = true

    headers = {
      "Authorization" => "Bearer #{ENV.fetch('OPEN_AI_TOKEN', nil)}",
      "Content-Type" => "application/json",
      "OpenAI-Beta" => "assistants=v2"
    }

    request = Net::HTTP::Get.new(api_url.path, headers)
    # request.body = data.to_json

    response = http.request(request)

    handle_response(response)
  end

  ### Runs

  def self.run_list(thread_id)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))
    client.runs.list(thread_id:)
  end

  def self.run(thread_id, run_id)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))
    client.runs.retrieve(thread_id:, id: run_id)
  end

  def self.create_run(thread_id, assistant_id)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))
    data = {
      assistant_id:
    }
    client.runs.create(thread_id:, parameters: data)
  end

  def self.create_thread_run(assistant_id, menssage)
    api_url = URI.parse("#{API_BASE_URL}/threads/runs")

    http = Net::HTTP.new(api_url.host, api_url.port)
    http.use_ssl = true

    headers = {
      "Authorization" => "Bearer #{ENV.fetch('OPEN_AI_TOKEN', nil)}",
      "Content-Type" => "application/json",
      "OpenAI-Beta" => "assistants=v2"
    }
    data = {
      assistant_id:,
      thread: {
        messages: [
          {
            role: "user",
            content: menssage
          }
        ]
      }
    }

    request = Net::HTTP::Post.new(api_url.path, headers)
    request.body = data.to_json

    response = http.request(request)

    handle_response(response)
  end

  def self.thread_run_steps(thread_id, run_id)
    api_url = URI.parse("#{API_BASE_URL}/threads/#{thread_id}/runs/#{run_id}/steps")

    http = Net::HTTP.new(api_url.host, api_url.port)
    http.use_ssl = true

    headers = {
      "Authorization" => "Bearer #{ENV.fetch('OPEN_AI_TOKEN', nil)}",
      "Content-Type" => "application/json",
      "OpenAI-Beta" => "assistants=v2"
    }

    request = Net::HTTP::Get.new(api_url.path, headers)
    # request.body = data.to_json

    response = http.request(request)

    handle_response(response)
  end

  def self.thread_run_verify(thread_id, run_id)
    api_url = URI.parse("#{API_BASE_URL}/threads/#{thread_id}/runs/#{run_id}")

    http = Net::HTTP.new(api_url.host, api_url.port)
    http.use_ssl = true

    headers = {
      "Authorization" => "Bearer #{ENV.fetch('OPEN_AI_TOKEN', nil)}",
      # 'Content-Type' => 'application/json',
      "OpenAI-Beta" => "assistants=v2"
    }

    request = Net::HTTP::Get.new(api_url.path, headers)
    response = http.request(request)

    handle_response(response)
  end

  def self.thread_run_step(thread_id, run_id, step_id)
    api_url = URI.parse("#{API_BASE_URL}/threads/#{thread_id}/runs/#{run_id}/steps/#{step_id}")

    http = Net::HTTP.new(api_url.host, api_url.port)
    http.use_ssl = true

    headers = {
      "Authorization" => "Bearer #{ENV.fetch('OPEN_AI_TOKEN', nil)}",
      "Content-Type" => "application/json",
      "OpenAI-Beta" => "assistants=v2"
    }

    request = Net::HTTP::Get.new(api_url.path, headers)
    # request.body = data.to_json

    response = http.request(request)

    handle_response(response)
  end

  def self.create_thread_run_submit(thread_id, run_id, ids = [])
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))
    tool_call_ids = []
    ids.each { |id| tool_call_ids.push({ tool_call_id: id, output: "" }) }
    data = { tool_outputs: tool_call_ids }
    client.runs.submit_tool_outputs(thread_id:, run_id:, parameters: data)
  end

  ## Files
  def self.file(id)
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))
    client.files.retrieve(id:)
  end

  def self.files
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))
    client.files.list
  end

  def self.funtions(answer, model_name = MODEL_NAME, _attachments = nil)
    data = {
      model: model_name,
      messages: [
        { role: "user", content: answer }
      ],
      temperature: 1,
      seed: 1,
      tools: [
        {
          type: "function",
          function: {
            name: "what_time_is",
            description: "funcion que me dice la hora de un pais en el mommento de solicitarla en tiempo real",
            parameters: {
              type: "object",
              properties: {
                location: {
                  type: "string",
                  description: "La ciudad  o pa\u00EDs a consultar; ejL cali, colombia o colombia"
                }
              },
              required: [ "location" ]
            }
          }
        }
      ],
      tool_choice: "auto"
    }

    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))

    response = client.chat(parameters: data)
    message = response.dig("choices", 0, "message")

    return unless message["role"] == "assistant" && message["tool_calls"]

    function_name = message["tool_calls"][0]["function"]["name"]

    args =
      JSON.parse(
        message["tool_calls"][0]["function"]["arguments"],
        { symbolize_names: true }
      )

    result = case function_name
    when "what_time_is"
               what_time_is(**args)
    end

    "Esta es la hora actual mi rey #{result}"
  end

  def self.what_time_is(_location)
    Time.zone = "America/New_York"
    current_time = Time.now.in_time_zone
    current_time.strftime("%H:%M:%S")
  end

  # solo jsonl
  # assistants, fine-tune
  # no mas de 20 archivos, cada uno no mas de 512 mb y el total no pude superar las 100 GB
  # y cada archivo no puede contener mas de 2.000.000 de tokens
  def self.file_up(attachments = nil, purpose = "fine-tune")
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))

    file = if attachments.include?("http")
             URI.open(attachments)
    else
             attachments
    end
    client.files.upload(parameters: { file:, purpose: })
  end

  def self.get_models
    api_url = URI.parse("#{API_BASE_URL}/models")

    http = Net::HTTP.new(api_url.host, api_url.port)
    http.use_ssl = true

    headers = {
      "Authorization" => "Bearer #{ENV.fetch('OPEN_AI_TOKEN', nil)}"
    }

    request = Net::HTTP::Get.new(api_url.path, headers)

    response = http.request(request)

    handle_response(response)
  end

  def self.speech(input, name, model_name = "tts-1", voice = "alloy")
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))

    response = client.audio.speech(
      parameters: {
        model: model_name,
        input:,
        voice:
      }
    )
    File.binwrite(name, response)

    file = File.open(name)
    url = IdearFile.upload(file, name)
    "#{ENV.fetch('DOORKEEPER_SITE', nil)}#{url}"
  end

  def self.translate(input, _language = "en", model_name = "whisper-1")
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))

    file = if input.start_with?("http")
             File.open(IdearFile.download(input))
    else
             File.open(input)
    end

    response = client.audio.translate(
      parameters: {
        model: model_name,
        file:
      }
    )
    response["text"]
  end

  def self.transcribe(input, language = "es", model_name = "whisper-1")
    client = OpenAI::Client.new(access_token: ENV.fetch("OPEN_AI_TOKEN", nil))

    file = if input.start_with?("http")
             File.open(IdearFile.download(input))
    else
             File.open(input)
    end

    client.audio.transcribe(
      parameters: {
        model: model_name,
        file:,
        language:
      }
    )
  end

  def self.images(content, amount = 1, size = "1024x1024", model_name = "dall-e-3")
    api_url = URI.parse("#{API_BASE_URL}/images/generations")
    data = {
      model: model_name,
      prompt: content,
      n: amount,
      size:
    }

    make_request(api_url, data)
  end

  def self.make_request(api_url, data)
    http = Net::HTTP.new(api_url.host, api_url.port)
    http.use_ssl = true # Habilita SSL para conexiones seguras

    headers = {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{ENV.fetch('OPEN_AI_TOKEN', nil)}"
    }

    request = Net::HTTP::Post.new(api_url.path, headers)
    request.body = data.to_json

    response = http.request(request)

    handle_response(response)
  end

  def self.handle_response(response)
    if response.code.to_i == 200
      process_successful_response(response)
    else
      process_error_response(response)
    end
  end

  def self.process_successful_response(response)
    if JSON.parse(response.body)["choices"]
      JSON.parse(response.body)["choices"]
    elsif JSON.parse(response.body)["data"]
      JSON.parse(response.body)["data"]
    else
      JSON.parse(response.body)
    end
  end

  def self.process_error_response(response)
    Rails.logger.debug { "Error: #{response.code} - #{response.message}" }
  end
end
