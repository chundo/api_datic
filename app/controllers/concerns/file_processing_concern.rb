# frozen_string_literal: true

module FileProcessingConcern
    extend ActiveSupport::Concern

    private

    def valid_file_presence?
      params["file"].present?
    end

    def valid_file_extension?(file_path)
      allowed_extensions = [ ".txt", ".md" ]
      File.extname(file_path).downcase.in?(allowed_extensions)
    end

    def load_prompt(file_path: nil, raw_text: nil)
      # TODO: transcribir
      return { error: "Debe prop  orcionar un archivo o texto" } if file_path.blank? && raw_text.blank?

      if file_path.present?
        read_file_content(file_path)
      else
        process_raw_text(raw_text)
      end
    end

    def process_raw_text(text)
      clean_text = text.strip
      return { error: "Texto no puede estar vacío" } if clean_text.empty?

      {
        content: clean_text,
        source: :direct_input,
        metadata: {
          length: clean_text.length,
          lines: clean_text.lines.count
        }
      }
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

    def valid_url?(path)
      uri = begin
        URI.parse(path)
      rescue StandardError
        nil
      end
      uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
    end

    def read_local_file(file_path)
      # Validaciones locales existentes
      return { error: "Archivo no encontrado" } unless File.exist?(file_path)
      return { error: "El path no es un archivo" } unless File.file?(file_path)
      return { error: "Extensión no permitida" } unless valid_file_extension?(file_path)

      begin
        content = File.read(file_path, encoding: "UTF-8").strip
        return { error: "Archivo vacío" } if content.empty?

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

    # Placeholder para fetch_remote_file, ya que no está definido en el código original
    def fetch_remote_file(url)
      # Implementa la lógica para descargar un archivo remoto si lo necesitas
      { error: "Descarga de archivos remotos no implementada" }
    end
end
