# frozen_string_literal: true

module Api
  module V1
    class HomeController < ApplicationController
      # # Instanciar el handler
      # handler = AiModelHandler.new({})
      # response = handler.generate('Hola', model: 'openai', model_version: 'gpt-4o-mini')

      def index
        render json: {
          localhost: ENV.fetch("LOCALHOST", nil),
          env: Rails.env,
          default_lenguage: I18n.default_locale,
          locale_lenguage: params[:locale],
          wellcome: I18n.t("hello")
        }, status: :ok
      end

      def convert_to_json
        # ConvertTo.csv_to_json()
        # params["file"]
        file = params["file"]

        # ConvertTo.csv_to_json(file)
        data = ConvertTo.csv_json(file)



        file_type = get_file_type(params["file"].content_type)
        render json: { file_type: file_type }, status: :ok
      end

      def youtube_metadata
        video_url = params[:url]

        if video_url.nil?
          return "debe proporcionar una url"
        end

        # data = Videos.extract_youtube_metadata(video_url)
        # data = Videos.extract_video_data(video_url)
        # comments = Videos.extract_video_comments(video_url)
        data = Videos.donwload_youtube_metadata(video_url)

        render json: data, status: :ok
      end

      # file - Archivo
      # q - consulta sobre el archivo a la ai
      # use_aws - usar aws
      def file_transcribe
        unless valid_file_presence?
          render json: { error: I18n.t("file.not_send") }, status: :unprocessable_entity
          return
        end

        file = convert_audio_file(params["file"])

        # transcription_result = WhisperService.transcribe_file(file_path: file)
        # transcription_result = WhisperService.transcribe_file(file_path: params["file"])
        transcription_result = WhisperService.transcribe_and_check_status(file_path: params["file"])

        if transcription_result[:success] && transcription_result[:status_response][:response]
          if transcription_result[:status_response][:response]["status"] == "completed"
            token = transcription_result[:token]
            transcription_result = transcription_result
          else
            token = transcription_result[:token]
            transcription_result = check_transcription_status_until_completed(token)
          end
        end

        if params[:q]
          handler = AiModelHandler.new({})
          response = handler.generate("#{params[:q]}: ####{transcription_result[:transcription]}###", model: "openai", model_version: "gpt-4o-mini")
          if response && !response.empty? # Verificamos que response no sea nil ni vacío
            transcription_result[:q_response] = response # Agregamos el nuevo atributo
          end
        end

        if transcription_result.is_a?(Hash) && transcription_result.key?(:error)
          render json: { error: transcription_result[:error] }, status: :unprocessable_entity
        elsif transcription_result.is_a?(Hash) && transcription_result.key?(:errors)
          render json: { errors: transcription_result[:errors] }, status: :bad_request
        elsif transcription_result.is_a?(Hash) && transcription_result[:success]
          render json: transcription_result, status: :ok
        end
      end

      def transcribe
        unless valid_file_presence?
          render json: { error: I18n.t("file.not_send") }, status: :unprocessable_entity
          return
        end

        # transcription_result = TranscriptionService.new(file: params["file"], params: params).transcribe
        transcription_result = WhisperService.transcribe_and_check_status(file_path: params["file"])

        if transcription_result[:success] && transcription_result[:status_response][:response]
          if transcription_result[:status_response][:response]["status"] == "completed"
            token = transcription_result[:token]
            transcription_result = transcription_result
          else
            token = transcription_result[:token]
            transcription_result = check_transcription_status_until_completed(token)
          end
        end

        if params[:q]
          handler = AiModelHandler.new({})
          response = handler.generate("#{params[:q]}: ####{transcription_result[:transcription]}###", model: "openai", model_version: "gpt-4o-mini")
          if response && !response.empty? # Verificamos que response no sea nil ni vacío
            transcription_result[:q_response] = response # Agregamos el nuevo atributo
          end
        end

        # verificar el estado de la transcripción si no está completa
        token = transcription_result[:token]

        if transcription_result.is_a?(Hash) && transcription_result.key?(:error)
          render json: { error: transcription_result[:error] }, status: :unprocessable_entity
        elsif transcription_result.is_a?(Hash) && transcription_result.key?(:errors)
          render json: { errors: transcription_result[:errors] }, status: :bad_request
        elsif transcription_result.is_a?(Hash) && transcription_result[:success]
          render json: transcription_result, status: :ok
        end
      end

      def routine_completions
        unless params[:q]
          render json: { error: "requiere una consulta" }, status: :unprocessable_entity
          return
        end

        query = params[:q]
        prompt = load_prompt(file_path: "prompts/instructions/routine.txt")
        new_prompt = prompt[:content].gsub("[inserta aquí el problema o consulta]", "####{query}###")

        handler = AiModelHandler.new({})
        response = handler.generate(new_prompt, model: "openai", model_version: "gpt-4o-mini")

        render json: response, status: :ok
      end

      def data_agent_scraping
        unless params[:q]
          render json: { error: "requiere una consulta" }, status: :unprocessable_entity
          return
        end

        query = params[:q]
        url = params[:url]
        prompt = load_prompt(file_path: "prompts/instructions/data_scraping.txt")

        new_prompt = prompt[:content].gsub("[inserta aquí la HTML]", "####{html}###").gsub("[inserta aquí la consulta]", "#{query} ").gsub("[inserta aquí la URL]", url)
        handler = AiModelHandler.new({})
        # # response = handler.generate(new_prompt, model: 'openai', model_version: 'gpt-4o-mini')
        response = handler.generate(new_prompt, model: "grok")
        data = response[:response] # JSON.parse(response[:response])

        render json: data, status: :ok
      end

      def agent_scraping
        unless params[:q]
          render json: { error: "requiere una consulta" }, status: :unprocessable_entity
          return
        end

        query = params[:q]
        prompt = load_prompt(file_path: "prompts/instructions/scraping.txt")

        new_prompt = prompt[:content].gsub("[inserta aquí el HTML o la consulta]", "#{query} ####{html}###")
        handler = AiModelHandler.new({})
        # # response = handler.generate(new_prompt, model: 'openai', model_version: 'gpt-4o-mini')
        response = handler.generate(new_prompt, model: "grok")

        render json: response, status: :ok
      end

      def completion
        handler = AiModelHandler.new({})
        prompt = params[:prompt]
        model = params[:model] || "local"
        response = handler.generate(prompt_params: prompt, model: model)
        data = response

        render json: data, status: :ok
      end

      def html
        url = params[:url]
        content = params[:content]
        q = params[:q]

        scraping = Scrapify.new(url, content, [])
        scrape = scraping.html(use_scraping: true, screen: false, slow_mo: 100)

        scrape
      end

      def data_format
        file = params["file"]
        result = load_prompt(file_path: "prompts/instruccion.txt")

        handler = AiModelHandler.new({})
        result = handler.generate("#{result[:content]}", model: "openai", model_version: "gpt-4o-mini-2024-07-18", attachments: file)

        render json: {
          success: true,
          data: result
        }, status: :ok
      end

      def public_calendar_ic
        # url = 'https://calendar.google.com/calendar/ical/segundo.espana%40cali.gov.co/private-89235a218387b54c3a9c864c57895dde/basic.ics'
        url = params["url"]
        response = HTTParty.get(url)

        if response.code == 200
          calendar = Icalendar::Calendar.parse(response.body).first
          calendar.events.last
          events = calendar.events.map do |event|
            attendees = event.attendee.map { |attendee| attendee.to_s.gsub("mailto:", "") }

            {
              uid: event.uid,
              type: event.name,
              dtstamp: event.dtstamp,
              dtstart: event.dtstart,
              dtend: event.dtend,
              summary: event.summary,
              description: event.description,
              location: event.location,
              status: event.status,
              organizer: event.organizer.to_s.sub("mailto:", ""),
              attendees:,
              custom_properties: event.custom_properties
            }
          end
          render json: { events: }, status: :ok
        else
          render plain: "Error fetching the calendar", status: :bad_request
        end
      end


      private

      def convert_audio_file(file, record = nil)
        Rails.logger.info "Iniciando conversión de archivo: #{file.original_filename} (#{file.content_type})"

        begin
          # Crear tempfiles para entrada y salida
          input_tempfile = Tempfile.new([ "input", File.extname(file.original_filename) ])
          output_tempfile = Tempfile.new([ "output", ".wav" ])

          # Asegurar que los tempfiles no se eliminen inmediatamente
          input_tempfile.binmode
          output_tempfile.binmode

          # Copiar contenido del archivo subido al tempfile
          IO.copy_stream(file.tempfile, input_tempfile.path)
          input_tempfile.close

          # Configurar ffmpeg
          movie = FFMPEG::Movie.new(input_tempfile.path)

          # Convertir a WAV con parámetros específicos para transcripción
          movie.transcode(output_tempfile.path, %w[-acodec pcm_s16le -ac 1 -ar 16000])

          # Crear un objeto de tipo ActionDispatch::Http::UploadedFile con el archivo convertido
          converted_file = ActionDispatch::Http::UploadedFile.new(
            tempfile: output_tempfile,
            filename: "#{File.basename(file.original_filename, '.*')}.wav",
            type: "audio/wave"
          )

          # Registrar en log
          Rails.logger.info "Archivo de audio convertido: #{file.original_filename} -> #{converted_file.original_filename}"

          # Subir a Active Storage si se proporciona un registro
          if record.respond_to?(:audio_attachment)
            record.audio_attachment.attach(
              io: converted_file.tempfile,
              filename: converted_file.original_filename,
              content_type: converted_file.content_type
            )
            Rails.logger.info "Archivo convertido subido a Active Storage para el registro: #{record.class.name}##{record.id}"
          end

          # # También subir a S3 si es necesario (mantenemos esta opción)
          # if defined?(upload_file) # Verificamos si la función existe
          #   s3_result = upload_file(converted_file, "audio_converted/#{params[:event_id]}")
          #   Rails.logger.info "Archivo convertido subido a S3: #{s3_result[:url]}" if s3_result && s3_result[:url]
          # end

          converted_file
        rescue StandardError => e
          Rails.logger.error "Error al convertir audio: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          file # En caso de error, devolver el archivo original
        ensure
          # Asegurar que los archivos temporales se eliminen
          input_tempfile.unlink if input_tempfile&.path
          # No eliminamos output_tempfile aquí porque Active Storage lo necesita hasta que se procese
        end
      end


      def check_transcription_status_until_completed(token)
        max_retries = 6
        retries = 0
        interval = 5 # seconds

        while retries < max_retries
          transcription_result = WhisperService.check_transcription_status_with_token(token)
          return transcription_result if transcription_result[:response]["status"] == "completed"

          retries += 1
          sleep(interval)
        end

        # Después de 5 intentos, esperar intervalos más largos
        extended_retries = 6
        extended_interval = 30 # 1 minuto

        extended_retries.times do
          transcription_result = WhisperService.check_transcription_status_with_token(token)
          return transcription_result if transcription_result[:response]["status"] == "completed"

          sleep(extended_interval)
        end

        { error: "Transcription did not complete within the expected time." }
      end
    end
  end
end
