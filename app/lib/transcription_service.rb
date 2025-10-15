# frozen_string_literal: true

class TranscriptionService
    attr_reader :file, :params

    def initialize(file:, params:)
      @file = file
      @params = params
    end

    def transcribe
      return { errors: I18n.t("file.not_send") } unless valid_file_presence?

      validation_errors = validate_file
      return { errors: validation_errors } if validation_errors.any?

      begin
        file_type = get_file_type(file.content_type)
        file_to_process = file_type == :video ? convert_audio_file : file

        temp_file = create_temp_file(file_to_process)
        transcription_text = perform_transcription(temp_file.path)

        {
          success: true,
          transcription: transcription_text,
          file_info: {
            name: file.original_filename,
            type: file_type,
            size: file.size
          }
        }
        # TODO: agregar .es y .en locale de los errores
      rescue StandardError => e
        Rails.logger.error "Error en transcripción: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        { error: "Error en transcripción: #{e.message}" }
      ensure
        cleanup_temp_file(temp_file)
      end
    end

    private

    def valid_file_presence?
      file.present?
    end

    def get_file_type(content_type)
      if is_audio_file?(content_type)
        :audio
      elsif content_type.start_with?("text/") || content_type == "application/json"
        :text
      elsif content_type.start_with?("video/")
        :video
      elsif content_type == "application/pdf" || content_type.include?("word") ||
            content_type.include?("document") || content_type == "application/vnd.ms-excel" ||
            content_type.include?("spreadsheet")
        :document
      else
        :other
      end
    end

    def is_audio_file?(content_type)
      audio_types = [ "audio/wave", "audio/wav", "audio/mpeg", "audio/mp3", "audio/mp4", "video/mp4",
                     "audio/aac", "audio/ogg", "audio/flac", "audio/x-wav", "application/octet-stream" ]
      audio_types.include?(content_type)
    end

    def validate_file
      errors = []

      allowed_types = [ "text/plain", "application/pdf", "text/csv",
                       "audio/wave", "audio/wav", "audio/mpeg", "video/mp4",
                       "audio/mp4", "audio/aac", "audio/ogg", "audio/mp3", "application/octet-stream" ]
      unless allowed_types.include?(file.content_type)
        # TODO: agregar .es y .en locale de los tipos
        errors << "Tipo de archivo no permitido (#{file.content_type})"
      end

      max_size = 50250.megabytes
      # TODO: agregar .es y .en locale del tamano
      errors << "Tamaño excede el límite (#{max_size / 1.megabyte}MB)" if file.size > max_size

      errors
    end

    def convert_audio_file
      Rails.logger.info "Iniciando conversión de archivo: #{file.original_filename} (#{file.content_type})"

      begin
        input_tempfile = Tempfile.new([ "input", File.extname(file.original_filename) ])
        output_tempfile = Tempfile.new([ "output", ".wav" ])

        input_tempfile.binmode
        output_tempfile.binmode

        IO.copy_stream(file.tempfile, input_tempfile.path)
        input_tempfile.close

        movie = FFMPEG::Movie.new(input_tempfile.path)
        movie.transcode(output_tempfile.path, [ "-acodec pcm_s16le", "-ac 1", "-ar 16000" ])

        ActionDispatch::Http::UploadedFile.new(
          tempfile: output_tempfile,
          filename: "#{File.basename(file.original_filename, '.*')}.wav",
          type: "audio/wave"
        )
      rescue StandardError => e
        Rails.logger.error "Error al convertir audio: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
        file # Devolver el archivo original en caso de error
      ensure
        input_tempfile.unlink if input_tempfile&.path
      end
    end

    def create_temp_file(file_to_process)
      temp_file = Tempfile.new([ "transcription", File.extname(file_to_process.original_filename) ])
      temp_file.binmode
      temp_file.write(file_to_process.read)
      temp_file.close
      temp_file
    end

    def perform_transcription(file_path)
      if params["use_aws"] == "true" # || peso mayor a 25mb
        transcribe_with_aws(file_path: file_path) # [:text]
        # transcription_result = WhisperService.transcribe_file(temp_file.path)
      else
        handler = AiModelHandler.new({})
        result = handler.generate(".", model: "whisper", model_version: "whisper-1", attachments: file_path)
        result["text"]
      end
    end

    # Método para transcribir audio usando AWS SageMaker (Whisper)
    def transcribe_with_aws(file_path: nil, use_bedrock: false)
      # Rails.logger.info "Iniciando transcripción de archivo: #{file_path}"

      # begin
      #   # Configuración común de AWS
      #   aws_config = {
      #     access_key_id: ENV.fetch('AWS_ACCESS_KEY_ID', nil),
      #     secret_access_key: ENV.fetch('AWS_SECRET_ACCESS_KEY', nil),
      #     region: ENV['AWS_REGION'] || 'us-east-1'
      #   }

      #   file = File.read(file_path)
      #   content_type = case File.extname(file_path)
      #                  when '.wav' then 'audio/wav'
      #                  when '.wma' then 'audio/wma'
      #                  when '.mp3' then 'audio/mpeg'
      #                  when '.ogg' then 'audio/ogg'
      #                  when '.mp4' then 'video/mp4'
      #                  when '.flac' then 'audio/flac'
      #                  else 'application/octet-stream'
      #                  end

      #   if use_bedrock
      #     # Configurar cliente Bedrock Runtime
      #     bedrock = Aws::BedrockRuntime::Client.new(aws_config)

      #     # TODO: cambiar el id
      #     # Invocar Bedrock
      #     response = bedrock.invoke_model(
      #       model_id: ENV['AWS_MODEL_ID'],
      #       content_type:,
      #       body: file
      #     )

      #     # Procesar respuesta de Bedrock
      #     result = JSON.parse(response.body.read, symbolize_names: true)
      #     Rails.logger.info '[AWS Bedrock Transcription] Successfully transcribed audio'
      #   else
      #     # Configurar cliente SageMaker Runtime
      #     sagemaker = Aws::SageMakerRuntime::Client.new(aws_config)

      #     # TODO: cambiar el id
      #     # Invocar el endpoint de SageMaker
      #     response = sagemaker.invoke_endpoint(
      #       endpoint_name: ENV['AWS_ENDPOINT_NAME'],
      #       content_type:,
      #       body: file
      #     )

      #     # Procesar respuesta de SageMaker
      #     result = JSON.parse(response.body.read, symbolize_names: true)
      #     Rails.logger.info '[AWS SageMaker Transcription] Successfully transcribed audio with Whisper'
      #   end

      #   result
      # rescue Aws::SageMakerRuntime::Errors::ServiceError => e
      #   Rails.logger.error "[AWS SageMaker Transcription Error] #{e.message}"
      #   "Error en transcripción AWS: #{e.message}"
      #   # raise StandardError, "Error en servicio AWS SageMaker: #{e.message}"
      # rescue Aws::BedrockRuntime::Errors::ServiceError => e
      #   Rails.logger.error "[AWS Bedrock Transcription Error] #{e.message}"
      #   "Error en transcripción AWS: #{e.message}"
      #   # raise StandardError, "Error en servicio AWS Bedrock: #{e.message}"
      # rescue StandardError => e
      #   Rails.logger.error "[AWS Transcription Error] #{e.message}"
      #   "Error en transcripción AWS: #{e.message}"
      #   # raise StandardError, "Error en transcripción AWS: #{e.message}"
      # end
      # byebug

      transcription_result = WhisperService.transcribe_file(file_path: file_path)

      transcription_result[:response]["transcription"]
    end

    def cleanup_temp_file(temp_file)
      temp_file.unlink if temp_file&.path
    end
end
