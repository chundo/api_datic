# frozen_string_literal: true

require "ostruct"

module Api
  module V1
    class ActasController < ApplicationController
      def meet_summary
        url = params["url"]
        event_id = params["event_id"]
        event = find_calendar(url, event_id)

        unless acta_present?
          render json: { error: "Debe enviar el acta" }, status: :unprocessable_entity
          return
        end

        unless valid_file_presence?
          render json: { error: "Archivo no enviado" }, status: :unprocessable_entity
          return
        end

        validation_errors = validate_file
        if validation_errors.any?
          render json: { errors: validation_errors }, status: :bad_request
          return
        end

        # Verificar tipo de archivo y determinar si necesita conversión
        file_type = get_file_type(params["file"].content_type)

        file_to_process = case file_type
        when :audio
                            if needs_conversion?(params["file"])
                              convert_audio_file(params["file"])
                            else
                              params["file"]
                            end
        when :video
                            convert_audio_file(params["file"])
        else
                            params["file"]
        end

        begin
          file_metadata = if %i[audio video].include?(file_type)
                            transcribe_file
          else
                            extract_file_metadata(file_to_process)
          end

          # sleep(0.5)

          acta_data = process_acta(event)

          parsed_response = call_llm(event, acta_data, file_metadata)

          if parsed_response.blank?
            render json: { error: "Respuesta LLM vacía o inválida: #{e.message}" }, status: :bad_request
            return
          end

          document_path = generate_acta_document(parsed_response, acta_data, event)

          # email1 = event[:organizer]
          email2 = URI.decode_www_form_component(url)[/ical\/(.+?)\/private/, 1]
          email3 = "segundo.espana@cali.gov.co"
          email = [ email2, email3 ].join(", ")


          begin
            UserMailer.send_document({ title: "Acta generada #{acta_data[:acta_number]}",
                                     email: email,
                                     document: document_path }).deliver_now
          rescue ArgumentError => e
            UserMailer.send_error({ title: "Error",
                                      email: email,
                                      body: "Ocurrio un error" }).deliver_now
          end

          render json: success_response(parsed_response, acta_data, file_metadata, document_path, event), status: :ok
          # render json: {a: file_to_process, b: file_metadata}, status: :ok
          nil
        rescue ArgumentError => e
          render json: { error: "Formato de acta inválido: #{e.message}" }, status: :bad_request
        rescue StandardError => e
          render json: { error: "Error en generación de contenido: #{e.message}" }, status: :service_unavailable
        rescue StandardError => e
          render json: { error: "Error creando documento: #{e.message}" }, status: :unprocessable_entity
        rescue StandardError => e
          log_error(e)
          render json: { error: "Error inesperado: #{e.message}" }, status: :internal_server_error
        end
      end

      def transcribe
        file = params["file"]
        file_type = get_file_type(file.content_type)

        result = transcribe_file
        render json: {
          success: true,
          transcription: result,
          file_info: {
            name: file.original_filename,
            type: file_type,
            size: file.size
          },
          service: params["use_aws"] == "true" ? "aws_sagemaker" : "openai"
        }, status: :ok
      end

      def transcribe_file
        if params["file"].blank?
          render json: { error: "Archivo no enviado" }, status: :unprocessable_entity
          return
        end

        validation_errors = validate_file
        if validation_errors.any?
          render json: { errors: validation_errors }, status: :bad_request
          return
        end

        file = params["file"]

        begin
          # Determinar el tipo de archivo
          file_type = get_file_type(file.content_type)

          pp "--------------------AAUDIO 2--------------------"

          # Convertir a formato adecuado si es necesario
          # if file_type == :video
          #   converted_file = convert_audio_file(file)
          #   file_to_process = converted_file
          # elsif file_type == :audio && file.original_filename.include?(".ogg") || file.original_filename.include?(".ogg")
          #   pp "---------------------AUDIO 3--------------------"
          #   converted_file = convert_audio_file(file)
          #   file_to_process = converted_file
          # else
          #   file_to_process = file
          # end

          # Guardar el archivo temporalmente
          # temp_file = Tempfile.new([ "transcription", File.extname(file_to_process.original_filename) ])
          # temp_file.binmode
          # temp_file.write(file_to_process.read)
          # temp_file.close

          # Seleccionar el servicio de transcripción según los parámetros
          # if params["use_aws"] == "true"
          #   # Transcripción con AWS SageMaker Whisper
          #   transcription_result = transcribe_with_aws(temp_file.path)
          #   transcription_text = transcription_result[:text]
          # else
          #   # Transcripción con OpenAI
          #   transcription = OpenAi.transcribe(temp_file.path)
          #   transcription_text = transcription["text"]
          # end

          # byebug

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

          transcription_text = transcription_result # [:status_response][:response]["text"]
        rescue StandardError => e
          Rails.logger.error "Error en transcripción: #{e.message}"
          Rails.logger.error e.backtrace.join("\n")
          # render json: { error: "Error en transcripción: #{e.message}" }, status: :unprocessable_entity
          "Error en transcripción: #{e.message}"
        ensure
          # Limpiar archivos temporales
          # temp_file.unlink if temp_file&.path
        end
      end

      private

      def acta_present?
        params["acta"].present?
      end

      def valid_file_presence?
        params["file"].present?
      end

      def process_acta(_event)
        acta = params["acta"]
        acta_name = extract_acta_name(acta)

        encode_acta(acta)
        convert = ConvertTo.acta_csv_json(acta)
        acta_number = extract_acta_number(convert)

        {
          acta_name:,
          acta_number:,
          signed_attendees: JSON.parse(convert[:json_data]),
          info: convert[:info_Acta]
        }
      end

      def call_llm(event, acta_data, file)
        ## Obtener el promp
        # prompt = load_prompt(file_path: "prompts/instructions/instruccion.txt")
        # prompt = load_prompt(file_path: "prompts/instructions/instruccion1.txt")
        prompt = load_prompt(file_path: "prompts/instructions/instruccion2.txt") # ESTE

        ## llamar a los modelos
        api_keys = {
          openai: ENV.fetch("OPEN_AI_TOKEN", nil),
          aws_access_key: ENV.fetch("AWS_ACCESS_KEY_ID", nil),
          aws_secret_key: ENV.fetch("AWS_SECRET_ACCESS_KEY", nil),
          grock: ENV.fetch("GROK", nil)
        }

        handler = AiModelHandler.new(api_keys)

        ## data procesator
        prompt_params = {
          event:,
          acta: acta_data,
          summary: file
        }

        new_prompt = prompt[:content].gsub("[DATOS]", "####{prompt_params}###")

        result = if params[:model]
                   handler.generate(prompt_params: new_prompt, model: params[:model])
        else
                   handler.generate(prompt_params: new_prompt, model: "grok")
        end
        result ||= handler.generate(prompt_params: new_prompt, model: "openai", model_version: "gpt-4o")

        byebug

        result_object = OpenStruct.new(result)

        # Primero limpiamos el contenido de la respuesta
        raw_response = result_object[:response].gsub("```json", "").gsub("```", "").strip

        # Verificamos si el JSON está completo y lo parseamos
        begin
          parsed_response = JSON.parse(raw_response)
        rescue JSON::ParserError => e
          Rails.logger.debug { "Error al parsear JSON: #{e.message}" }

          # Intenta limpiar caracteres de escape innecesarios
          fixed_json = raw_response.gsub("\n", "").gsub("\t", "").gsub("\r", "")

          begin
            parsed_response = JSON.parse(fixed_json)
          rescue JSON::ParserError => e
            Rails.logger.debug { "Error al intentar reparar JSON: #{e.message}" }
            parsed_response = nil
          end
        end
        parsed_response
      end

      def extract_acta_name(acta)
        acta.is_a?(String) ? File.basename(acta) : acta.original_filename
      end

      def encode_acta(acta)
        Base64.encode64(acta.read).force_encoding("UTF-8")
      end

      def extract_acta_number(convert_data)
        convert_data[:info_Acta][:acta_number].split.last
      end

      def event_summary(event)
        {
          event_id: event[:uid],
          title: event[:summary],
          start_time: event[:dtstart],
          end_time: event[:dtend],
          type: event[:type],
          created: event[:dtstamp],
          description: event[:description],
          location: event[:location],
          status: event[:status],
          organizer: event[:organizer],
          participants_count: event[:attendees].count
        }
      end

      def find_calendar(url, event_id)
        return { error: "URL inv\u00E1lida" } if url.blank?
        return { error: "Event ID requerido" } if event_id.blank?

        begin
          response = HTTParty.get(url, timeout: 10)

          return { error: "Error al obtener calendario: HTTP #{response.code}" } unless response.success?

          calendar = Icalendar::Calendar.parse(response.body).first
          return { error: "Calendario no encontrado" } unless calendar

          event = calendar.events.find { |e| e.uid == event_id }
          return { error: "Evento #{event_id} no encontrado" } unless event

          attendees = event.attendee.to_a.map do |a|
            a = a.to_s
            a.gsub!(/^(mailto:|MATMSG:)/i, "")
            a.split(";").first.strip
          end

          {
            uid: event.uid,
            type: event.name,
            dtstamp: event.dtstamp,
            dtstart: event.dtstart,
            dtend: event.dtend,
            summary: event.summary,
            description: event.description,
            location: event.custom_properties["x_google_conference"][0],
            status: event.status,
            organizer: event.organizer.to_s.sub("mailto:", ""),
            attendees:
          }
        rescue HTTParty::Error => e
          { error: "Error de conexión: #{e.message}" }
        rescue Icalendar::ParseError => e
          { error: "Calendario inválido: #{e.message}" }
        rescue StandardError => e
          { error: "Error inesperado: #{e.message}" }
        end
      end

      def validate_file
        errors = []

        # Validación de tipo de archivo
        allowed_types = [ "text/plain", "application/pdf", "text/csv",
                         "audio/wave", "audio/wav", "audio/mpeg", "video/mp4",
                         "audio/mp4", "audio/aac", "audio/ogg" ]
        unless allowed_types.include?(params["file"].content_type)
          errors << "Tipo de archivo no permitido (#{params['file'].content_type})"
        end

        # Validación de tamaño máximo (10MB)
        max_size = 250.megabytes
        errors << "Tamaño excede el límite (#{max_size / 1.megabyte}MB)" if params["file"].size > max_size

        errors
      end

      # Método para determinar el tipo de archivo (audio, texto, documento, etc.)
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
        audio_types = [ "audio/wave", "audio/wav", "audio/mpeg", "audio/mp3", "audio/mp4",
                       "audio/aac", "audio/ogg", "audio/flac", "audio/x-wav" ]
        audio_types.include?(content_type)
      end

      # Método para comprobar si un archivo necesita conversión
      def needs_conversion?(file)
        return false unless file

        file_type = get_file_type(file.content_type)

        # Solo convertir archivos de audio que no estén ya en formato WAV óptimo
        if file_type == :audio
          # Si ya es WAV, no necesita conversión
          if [ "audio/wave", "audio/wav" ].include?(file.content_type)
            # Idealmente aquí verificaríamos los parámetros internos del WAV
            # pero por simplicidad asumimos que no necesita conversión
            return false
          end

          return true
        end

        # Archivos de texto, documentos u otros tipos no necesitan conversión
        false
      end

      # Método para convertir archivos de audio utilizando ffmpeg
      def convert_audio_file(file, record = nil)
        Rails.logger.info "Iniciando conversión de archivo: #{file.original_filename} (#{file.content_type})"

        pp "----------KLK"


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

      # ver
      def extract_file_data
        file = params["file"]

        # Leer contenido una sola vez
        file_content = file.is_a?(String) ? File.read(file) : file.read

        {
          name: extract_filename(file),
          #   encoded: Base64.strict_encode64(file_content),
          summary: file_content # [0..500] # Primeros 500 caracteres || OJO IMPLEMENTAR RESUMEN
        }
      ensure
        # Rebobinar el archivo para futuros accesos
        file.rewind if file.respond_to?(:rewind)
      end

      #   def extract_filename(file)
      #     if file.is_a?(String)
      #       File.basename(file)
      #     else
      #       file.original_filename.encode('UTF-8', invalid: :replace, undef: :replace)
      #     end
      #   end

      def extract_filename(file, response = nil)
        if response.present?
          # Intentar obtener de Content-Disposition
          disposition = response.headers["content-disposition"].to_s
          filename = disposition[/filename="?([^"]+)"?/, 1]

          # Si no se encuentra, usar el path de la URL
          filename ||= File.basename(URI.parse(file).path)

          # Sanitizar nombre
          filename.gsub(/[^\w\.\-]/, "_")
        elsif file.is_a?(String)
          File.basename(file)
        else
          file.original_filename.encode("UTF-8", invalid: :replace, undef: :replace)
        end
      end

      # Falta no esta implementado
      def upload_file
        file = params[:file]
        uploader = S3Uploader.new
        uploader.upload_file(file, "custom_prefix/#{params[:event_id]}")

      #   render json: {
      #     message: 'Archivo subido exitosamente',
      #     s3_data: result
      #   }
      rescue S3Uploader::UploadError
        #   render json: { error: e.message }, status: :unprocessable_entity
      end

      # Falta no esta imlementado
      def upload
        file = params[:file]
        uploader = S3Uploader.new
        result = uploader.upload_file(file, "custom_prefix/#{params[:event_id]}")

        render json: {
          message: "Archivo subido exitosamente",
          s3_data: result
        }
      rescue S3Uploader::UploadError => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def load_prompt(file_path: nil, raw_text: nil)
        return { error: "Debe proporcionar un archivo o texto" } if file_path.blank? && raw_text.blank?

        if file_path.present?
          read_file_content(file_path)
        else
          process_raw_text(raw_text)
        end
      end

      def read_file_content(file_path)
        # Determinar si es URL o archivo local
        if valid_url?(file_path)
          fetch_remote_file(file_path)
        else
          read_local_file(file_path)
        end
      rescue StandardError => e
        { error: "Error procesando recurso: #{e.message}" }
      end

      def read_local_file(file_path)
        # Validaciones locales existentes
        return { error: "Archivo no encontrado" } unless File.exist?(file_path)
        return { error: "El path no es un archivo" } unless File.file?(file_path)
        return { error: "Extensi\u00F3n no permitida" } unless valid_file_extension?(file_path)

        begin
          content = File.read(file_path, encoding: "UTF-8").strip
          return { error: "Archivo vac\u00EDo" } if content.empty?

          {
            content:,
            source: :file,
            metadata: {
              path: File.expand_path(file_path),
              size: File.size(file_path),
              modified: File.mtime(file_path),
              sha256: Digest::SHA256.file(file_path).hexdigest
            }
          }
        rescue Errno::EACCES => e
          { error: "Error de permisos: #{e.message}" }
        rescue EncodingError => e
          { error: "Problema de codificación: #{e.message}" }
        end
      end

      def fetch_remote_file(url)
        # Validaciones de seguridad para URLs
        raise "URL no permitida" unless allowed_url?(url)

        response = HTTParty.get(
          url,
          timeout: 15,
          follow_redirects: true,
          verify: true # Verificar certificados SSL
        )

        # Manejar códigos de estado HTTP
        raise "Error HTTP #{response.code}" unless response.success?

        # Validar tipo de contenido
        content_type = response.headers["content-type"].split(";").first
        raise "Tipo de contenido no permitido (#{content_type})" unless valid_content_type?(content_type)

        # Obtener nombre de archivo
        filename = extract_filename(url, response)

        {
          content: response.body.force_encoding("UTF-8").scrub.strip,
          source: :url,
          metadata: {
            url:,
            final_url: response.request.last_uri.to_s,
            filename:,
            content_type:,
            size: response.body.bytesize,
            headers: response.headers.slice("date", "last-modified", "etag")
          }
        }
      end

      # Helpers de validación
      def valid_url?(path)
        uri = begin
          URI.parse(path)
        rescue StandardError
          nil
        end
        uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
      end

      def allowed_url?(url)
        allowed_domains = [ "digitalocean.com", "ideardev.com", "perldoc.perl.org", "cali.gov.co" ]
        uri = URI.parse(url)
        allowed_domains.include?(uri.host)
      end

      def valid_content_type?(content_type)
        allowed_types = [ "text/plain", "application/pdf", "text/csv" ]
        allowed_types.include?(content_type)
      end

      def process_raw_text(text)
        clean_text = text.strip
        return { error: "Texto no puede estar vac\u00EDo" } if clean_text.empty?

        {
          content: clean_text,
          source: :direct_input,
          metadata: {
            length: clean_text.length,
            lines: clean_text.lines.count
          }
        }
      end

      def valid_file_extension?(file_path)
        allowed_extensions = [ ".txt", ".md" ]
        File.extname(file_path).downcase.in?(allowed_extensions)
      end

      # no esta en uso no implementado
      def get_instructions
        result = load_prompt(
          file_path: params[:file_path],
          raw_text: params[:text]
        )

        if result[:error]
          render json: { error: result[:error] }, status: :bad_request
        else
          render json: {
            prompt: result[:content],
            source: result[:source],
            metadata: result[:metadata]
          }
        end
      end

      def document(data, acta_data, event)
        acta_number =  acta_data[:acta_number] || data[:acta_number]
        # Verificar existencia del template
        template_path = "acta_model.docx"
        raise "Archivo plantilla #{template_path} no encontrado" unless File.exist?(template_path)

        # Mapeo de placeholders con claves del hash
        placeholders = {
          "###ACTANUMBER###" => :acta_number,
          "###INITD###" => :initial_date,
          "###INITHS###" => :start_hour,
          "###INITHF###" => :end_hour,
          "###OBJETIVE###" => :objective,
          "###MEETLINK###" => :link,
          "###ATTENDEES###" => :attendees,
          "###ABSENTEES###" => :absentees,
          "###INVITED###" => :invited,
          "###AGENDA###" => :agenda,
          "###DEVELOPMENT###" => :development,
          "###TASKS###" => :tasks,
          "###SIGNATURES###" => :signatures,
          "###ORGANIZER###" => :organizer
        }

        begin
          doc = Docx::Document.open(template_path)

          # Procesar todos los elementos del documento
          process_document(doc, placeholders, data, acta_data, event)

          output_path = "acta_#{acta_number}_#{Time.zone.now.strftime('%Y%m%d')}.docx"
          doc.save(output_path)

          { success: true, file_path: output_path }
        rescue StandardError => e
          { success: false, error: "Error generando documento: #{e.message}" }
        end
      end

      def process_document(doc, placeholders, data, acta_data, event)
        # Procesar tablas y párrafos
        doc.tables.each do |table|
          table.rows.each do |row|
            row.cells.each do |cell|
              process_paragraphs(cell.paragraphs, placeholders, data, acta_data, event)
            end
          end
        end

        process_paragraphs(doc.paragraphs, placeholders, data, acta_data, event)
      end

      def process_paragraphs(paragraphs, placeholders, data, acta_data, event)
        paragraphs.each do |paragraph|
          paragraph.each_text_run do |text_run|
            placeholders.each do |placeholder, key|
              # Usar la función helper para extraer el valor correcto
              # byebug
              value = extract_value_by_key(key, data, acta_data, event)

              if key == :initial_date
                value = acta_data[:info][:data_start].split(":")[1].strip if acta_data[:info] && acta_data[:info][:data_start]
              end
              if key ==  :absentees
                value = "N/A"
              end
              if key ==  :invited
                value = "N/A"
              end
              # if key == :signatures
              #   value = "N/A"
              # end
              if key == :organizer
                value = data[:organizer]
              end
              # Validar aqui los inputs

              next unless value.present? # Saltar si no hay dato en ningún objeto

              # Procesar saltos de línea si es necesario
              processed_value = value.to_s.gsub("\n", "\r\n")

              text_run.substitute(placeholder, processed_value)
            end
          end
        end
      end

      # Función para extraer el valor correcto basándose en el key del atributo
      def extract_value_by_key(key, data, acta_data, event)
        if key.is_a?(Symbol) && key.to_s.end_with?("acta_number")
          return acta_data[:acta_number] || data[:acta_number] || event[:acta_number]
        elsif key.is_a?(Symbol) && key.to_s.end_with?("initial_date")
          # Formatear la fecha de event[:dtstart] o usar data[:initial_date] como fallback
          if event[:dtstart].present?
            return format_date_to_spanish(event[:dtstart])
          else
            return data[:initial_date]
          end
        elsif key.is_a?(Symbol) && key.to_s.end_with?("objetive")
          return event[:summary] || data[:objective] || "No disponible"
        elsif key.is_a?(Symbol) && key.to_s.end_with?("link")
          return event[:location] || data[:link] || "No disponible"
        elsif key.is_a?(Symbol) && key.to_s.end_with?("attendees")
          return data[:attendees]
        end
        # # Prioridad: data -> acta_data -> event
        return data[key] if data.is_a?(Hash) && data.key?(key) && data[key].present?
        return acta_data[key] if acta_data.is_a?(Hash) && acta_data.key?(key) && acta_data[key].present?
        return event[key] if event.is_a?(Hash) && event.key?(key) && event[key].present?

        # Si los objetos no son Hash, intentar acceder como OpenStruct
        return data.send(key) if data.respond_to?(key) && data.send(key).present?
        return acta_data.send(key) if acta_data.respond_to?(key) && acta_data.send(key).present?
        return event.send(key) if event.respond_to?(key) && event.send(key).present?

        # Retornar nil si no se encuentra el valor en ningún objeto
        nil
      end

      def extract_file_metadata(uploaded_file)
        file_content = uploaded_file.is_a?(String) ? File.read(uploaded_file) : uploaded_file.read

        # {
        #   name: extract_filename(file),
        #   #   encoded: Base64.strict_encode64(file_content),
        #   summary: file_content # [0..500] # Primeros 500 caracteres || OJO IMPLEMENTAR RESUMEN
        # }

        {
          filename: uploaded_file.original_filename,
          #   summary: Base64.strict_encode64(file_content), #generate_file_summary(uploaded_file),
          summary: file_content,
          metadata: {
            size: uploaded_file.size,
            mime_type: uploaded_file.content_type
          }
        }
      end

      def build_acta_data(event, file_metadata)
        base_data = process_acta(event)
        base_data.merge(
          event_summary(event),
          file_metadata:
        )
      end

      def generate_acta_document(llm_response, acta_data, event)
        llm_response_new = OpenStruct.new(llm_response)
        raise StandardError, "Datos incompletos para documento" unless valid_document_data?(llm_response_new)

        return unless llm_response_new

        document(llm_response_new, acta_data, event)
      end

      def success_response(llm_data, acta_data, file_metadata, document_path, event)
        {
          result: llm_data,
          event:,
          acta_data:,
          summary_data: file_metadata,
          document: {
            path: document_path
            # url: generate_document_url(document_path)
          },
          timestamp: Time.current.iso8601
        }
      end

      # Helpers de validación

      def valid_document_data?(data)
        required_fields = %i[acta_number initial_date attendees]
        required_fields.all? { |field| data[field].present? }
      end

      def log_error(error)
        Rails.logger.error "[ActaService] #{error.class}: #{error.message}"
        Rails.logger.error error.backtrace.join("\n")
      end

      # Método para transcribir audio usando AWS SageMaker (Whisper)
      def transcribe_with_aws(file_path, use_bedrock: false)
        Rails.logger.info "Iniciando transcripción de archivo: #{file_path}"

        begin
          # Configuración común de AWS
          aws_config = {
            access_key_id: ENV.fetch("AWS_ACCESS_KEY_ID", nil),
            secret_access_key: ENV.fetch("AWS_SECRET_ACCESS_KEY", nil),
            region: ENV["AWS_REGION"] || "us-east-1"
          }

          # Leer el archivo de audio y convertirlo a Base64
          # audio_content = File.binread(file_path)
          # encoded_audio = Base64.strict_encode64(audio_content)

          file = File.read(file_path)
          content_type = case File.extname(file_path)
          when ".wav" then "audio/wav"
          when ".wma" then "audio/wma"
          when ".mp3" then "audio/mpeg"
          when ".ogg" then "audio/ogg"
          when ".mp4" then "video/mp4"
          when ".flac" then "audio/flac"
          else "application/octet-stream"
          end

          if use_bedrock
            # Configurar cliente Bedrock Runtime
            bedrock = Aws::BedrockRuntime::Client.new(aws_config)

            # Invocar Bedrock
            response = bedrock.invoke_model(
              model_id: Settings.aws.whisper_model,
              content_type:,
              body: file
            )

            # Procesar respuesta de Bedrock
            result = JSON.parse(response.body.read, symbolize_names: true)
            Rails.logger.info "[AWS Bedrock Transcription] Successfully transcribed audio"
          else
            # Configurar cliente SageMaker Runtime
            sagemaker = Aws::SageMakerRuntime::Client.new(aws_config)

            # Invocar el endpoint de SageMaker
            response = sagemaker.invoke_endpoint(
              endpoint_name: Settings.aws.whisper_name,
              content_type:,
              body: file
            )

            # Procesar respuesta de SageMaker
            result = JSON.parse(response.body.read, symbolize_names: true)
            Rails.logger.info "[AWS SageMaker Transcription] Successfully transcribed audio with Whisper"
          end

          result
        rescue Aws::SageMakerRuntime::Errors::ServiceError => e
          Rails.logger.error "[AWS SageMaker Transcription Error] #{e.message}"
          "Error en transcripción AWS: #{e.message}"
          # raise StandardError, "Error en servicio AWS SageMaker: #{e.message}"
        rescue Aws::BedrockRuntime::Errors::ServiceError => e
          Rails.logger.error "[AWS Bedrock Transcription Error] #{e.message}"
          "Error en transcripción AWS: #{e.message}"
          # raise StandardError, "Error en servicio AWS Bedrock: #{e.message}"
        rescue StandardError => e
          Rails.logger.error "[AWS Transcription Error] #{e.message}"
          "Error en transcripción AWS: #{e.message}"
          # raise StandardError, "Error en transcripción AWS: #{e.message}"
        end
      end

      # Función para formatear fecha al formato español "dd/mmm/yyyy"
      def format_date_to_spanish(date_time)
        return nil unless date_time.present?

        begin
          # Convertir a objeto Time si es necesario
          parsed_date = case date_time
          when String
                         Time.parse(date_time)
          when DateTime, Time
                         date_time
          else
                         return nil
          end

          # Mapeo de meses en español
          months_spanish = {
            1 => "ene", 2 => "feb", 3 => "mar", 4 => "abr",
            5 => "may", 6 => "jun", 7 => "jul", 8 => "ago",
            9 => "sep", 10 => "oct", 11 => "nov", 12 => "dic"
          }

          day = parsed_date.day.to_s.rjust(2, "0")
          month = months_spanish[parsed_date.month]
          year = parsed_date.year

          "#{day}/#{month}/#{year}"
        rescue StandardError => e
          Rails.logger.error "Error formateando fecha: #{e.message}"
          nil
        end
      end
    end
  end
end
