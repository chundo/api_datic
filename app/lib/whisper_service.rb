# frozen_string_literal: true

require "uri"
require "net/http"
require "json"
require "httparty"

class WhisperService
  # Realiza una solicitud al servicio de transcripción para transcribir un archivo
  # @param file_path [String] Ruta al archivo a transcribir
  # @param model_name [String] Nombre del modelo a usar para la transcripción (por ejemplo, "turbo")
  # @return [Hash] Respuesta del servicio o un hash con error
  def self.transcribe_file(file_path:, model_name: "turbo")
    # Verificar que el archivo exista
    unless File.exist?(file_path)
      return { success: false, error: "Archivo no encontrado: #{file_path}" }
    end

    # Abrir el archivo para enviarlo
    file = File.open(file_path, "rb")

    begin
      # Construir la URL con el parámetro model_name
      # url = "#{Settings.whisper_server}/transcribe/?model_name=#{model_name}"
      url = "#{Settings.whisper_server}/api/request/transcription"

      # Realizar la solicitud POST con multipart/form-data
      response = HTTParty.post(
        url,
        body: {
          audio_file: file,
          model_name: model_name
        },
        headers: {
          "Content-Type" => "multipart/form-data",
          "X-API-Key" => ENV.fetch("WHISPER_TOKEN", nil)
        },
        timeout: 600 # Timeout de 5 minutos, ajustable según el tamaño del archivo
      )

      # Verificar si la solicitud fue exitosa
      if response.success?
        { success: true, response: response.parsed_response, status: response.code }
      else
        { success: false, error: "Error en la solicitud: #{response.code} - #{response.message}", body: response.body }
      end
    rescue HTTParty::Error => e
      { success: false, error: "Error HTTP: #{e.message}" }
    rescue StandardError => e
      { success: false, error: "Error inesperado: #{e.message}" }
    ensure
      file.close if file
    end
  end

  # Verifica el estado del servidor
  # @return [Hash] Respuesta del servicio o un hash con error
  def self.check_server_status
    begin
      # URL del endpoint de salud del servidor
      url = "#{Settings.whisper_server}/api/health"

      # Realizar la solicitud GET
      response = HTTParty.get(
        url,
        headers: {
          "X-API-Key" => ENV.fetch("WHISPER_TOKEN", nil)
        }
      )

      # Verificar si la solicitud fue exitosa
      if response.success?
        { success: true, response: response.parsed_response, status: response.code }
      else
        { success: false, error: "Error en la solicitud: #{response.code} - #{response.message}", body: response.body }
      end
    rescue HTTParty::Error => e
      { success: false, error: "Error HTTP: #{e.message}" }
    rescue StandardError => e
      { success: false, error: "Error inesperado: #{e.message}" }
    end
  end

  # Verifica el estado del servidor usando un token
  # @param token [String] Token único para la solicitud
  # @return [Hash] Respuesta del servicio o un hash con error
  def self.check_transcription_status_with_token(token)
    begin
      # URL del endpoint de estado del servidor con el token
      url = "#{Settings.whisper_server}/api/status/#{token}"

      # Realizar la solicitud GET
      response = HTTParty.get(
        url,
        headers: { "X-API-Key" => ENV.fetch("WHISPER_TOKEN", nil) }
      )

      # Verificar si la solicitud fue exitosa
      if response.success?
        { success: true, response: response.parsed_response, status: response.code }
      else
        { success: false, error: "Error en la solicitud: #{response.code} - #{response.message}", body: response.body }
      end
    rescue HTTParty::Error => e
      { success: false, error: "Error HTTP: #{e.message}" }
    rescue StandardError => e
      { success: false, error: "Error inesperado: #{e.message}" }
    end
  end

  # Combina el llamado de transcribe_file y verifica el estado de la transcripción si hay un token
  # @param file_path [String] Ruta al archivo a transcribir
  # @param model_name [String] Nombre del modelo a usar para la transcripción (por ejemplo, "turbo")
  # @return [Hash] Respuesta del servicio o un hash con error
  def self.transcribe_and_check_status(file_path:, model_name: "turbo")
    # Llamar a transcribe_file
    transcribe_response = transcribe_file(file_path: file_path, model_name: model_name)

    # Verificar si la respuesta contiene un token
    if transcribe_response[:success] && transcribe_response[:response]["token"]
      token = transcribe_response[:response]["token"]

      # Llamar a check_transcription_status_with_token con el token
      status_response = check_transcription_status_with_token(token)

      # Responder con el token y el resultado de check_transcription_status_with_token
      { success: true, token: token, status_response: status_response }
    else
      transcribe_response # Retornar la respuesta original si no hay token
    end
  end
end
