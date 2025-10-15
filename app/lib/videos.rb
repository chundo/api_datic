# frozen_string_literal: true

require 'open-uri'
require 'httparty'
require 'nokogiri'
require 'json'


class Videos
  def self.donwload_video(url, calidad = 'alta', ruta_destino = Dir.pwd)
    begin
      # Paso 1: Obtener el HTML de la página de YouTube
      response = HTTParty.get(url, headers: {'User-Agent' => 'Mozilla/5.0'})
      
      if response.code != 200
        puts "Error al acceder a la URL: Código #{response.code}"
        return nil
      end

      # Paso 2: Extraer la información del video
      html = Nokogiri::HTML(response.body)
      
      # Buscar los datos del video en el HTML (esto puede cambiar si YouTube actualiza su estructura)
      scripts = html.css('script').map(&:text)
      player_data = scripts.find { |script| script.include?('var ytInitialPlayerResponse = ') }
      
      if player_data.nil?
        puts "No se pudo encontrar la información del video"
        return nil
      end    

      # Extraer los datos JSON
      json_string = player_data.sub(/^var ytInitialPlayerResponse = /, '').sub(/\;$/, '')
      video_data = JSON.parse(json_string)



      # Obtener título del video
      # titulo = video_data['videoDetails']['title'].gsub(/[^0-9A-Za-z\s]/, '')
      
      # # Paso 3: Obtener el stream de video según la calidad seleccionada
      # streaming_data = video_data['streamingData']
      # formats = (streaming_data['formats'] || []) + (streaming_data['adaptiveFormats'] || [])
      
      # video_formats = formats.select { |f| f['mimeType'].include?('video/mp4') }
      
      # if video_formats.empty?
      #   puts "No se encontraron formatos de video"
      #   return nil
      # end

      # video_format = case calidad.downcase
      #                when 'alta'
      #                  video_formats.max_by { |f| f['bitrate'].to_i }
      #                when 'media'
      #                  sorted = video_formats.sort_by { |f| f['bitrate'].to_i }
      #                  sorted[sorted.length / 2]
      #                when 'baja'
      #                  video_formats.min_by { |f| f['bitrate'].to_i }
      #                else
      #                  video_formats.max_by { |f| f['bitrate'].to_i } # Por defecto, alta calidad
      #                end

      # byebug 
      # # Obtener el formato de audio
      # audio_format = formats.select { |f| f['mimeType'].include?('audio') }.max_by { |f| f['bitrate'].to_i }
      
      # if video_format.nil? || audio_format.nil?
      #   puts "No se pudieron obtener los streams de video o audio"
      #   return nil
      # end  

      # Paso 4: Descargar el video y el audio
      # video_url = video_format['url'] || streaming_data["serverAbrStreamingUrl"] || video_data['streamingData']["formats"][0]["url"]
      # audio_url = audio_format['url']
      
      # extension = video_format['mimeType'].match(/\/([a-z0-9]+);/i)[1]
      # video_path = "#{ruta_destino}/#{titulo}_video.#{extension}"
      # audio_path = "#{ruta_destino}/#{titulo}_audio.#{extension}"
      # output_path = "#{ruta_destino}/#{titulo}.#{extension}"

      # # Descargar el video
      # File.open(video_path, 'wb') do |file|
      #   file.write(URI.open(video_url).read)
      # end
      
      # # Descargar el audio
      # File.open(audio_path, 'wb') do |file|
      #   file.write(URI.open(audio_url).read)
      # end
      
      # # Paso 5: Combinar video y audio (requiere FFmpeg instalado)
      # system("ffmpeg -i #{video_path} -i #{audio_path} -c:v copy -c:a aac #{output_path}")
      
      # # Eliminar archivos temporales
      # File.delete(video_path)
      # File.delete(audio_path)
      
      # puts "Video descargado exitosamente: #{output_path}"
      return video_data
      
    rescue => e
      puts "Error al descargar el video: #{e.message}"
      return nil
    end
  end

  def self.extract_video_data(url, calidad = 'alta', ruta_destino = Dir.pwd)
    begin
      # Paso 1: Obtener el HTML de la página de YouTube
      response = HTTParty.get(url, headers: {'User-Agent' => 'Mozilla/5.0'})
      
      if response.code != 200
        puts "Error al acceder a la URL: Código #{response.code}"
        return nil
      end

      # Paso 2: Extraer la información del video
      html = Nokogiri::HTML(response.body)
      
      # Buscar los datos del video en el HTML (esto puede cambiar si YouTube actualiza su estructura)
      scripts = html.css('script').map(&:text)

      variables = []
      scripts.each do |script|
        # Buscar declaraciones de 'var' usando una expresión regular
        # Coincide con 'var nombre = ...' hasta el final de la línea o punto y coma
        script.scan(/var\s+([a-zA-Z_$][a-zA-Z0-9_$]*)\s*=/) do |match|
          variables << match[0] # Captura el nombre de la variable
        end
      end

      player_data = scripts.find { |script| script.include?('var ytInitialPlayerResponse = ') }
      
      if player_data.nil?
        puts "No se pudo encontrar la información del video"
        return nil
      end    

      # Extraer los datos JSON
      json_string = player_data.sub(/^var ytInitialPlayerResponse = /, '').sub(/\;$/, '')
      video_data = JSON.parse(json_string)

      return video_data      
    rescue => e
      puts "Error al descargar el video: #{e.message}"
      return nil
    end
  end

  def self.extract_youtube_metadata(video_url)
    # Path to the Python script
    python_script_path = 'app/lib/videos.py'

    # Validate the URL (basic check for YouTube URL format)
    unless video_url.match?(%r{^https?://(www\.youtube\.com|youtu\.be)})
      return { error: 'Invalid YouTube URL' }
    end

    # Command to execute the Python script with the video URL
    command = "python3 #{python_script_path} \"#{video_url}\""

    # Execute the Python script and capture output
    output = `#{command} 2>&1`
    success = $?.success?

    unless success
      return { error: "Failed to execute Python script: #{output}" }
    end

    begin
      metadata = JSON.parse(output)

      return metadata
    rescue JSON::ParserError => e
      return { error: "Failed to parse JSON output: #{e.message}" }
    end

  end

  def self.donwload_youtube_metadata(video_url)
    # Path to the Python script
    python_script_path = 'app/lib/videos.py'

    # Validate the URL (basic check for YouTube URL format)
    unless video_url.match?(%r{^https?://(www\.youtube\.com|youtu\.be)})
      return { error: 'Invalid YouTube URL' }
    end

    # Command to execute the Python script with the video URL
    command = "python3 #{python_script_path} \"#{video_url}\" --download --upload"

    # Execute the Python script and capture output
    output = `#{command} 2>&1`
    success = $?.success?

    unless success
      return { error: "Failed to execute Python script: #{output}" }
    end

    begin
      # metadata = JSON.parse(output)

      # return metadata
      # return { ok: , metadata: metadata }
      return output
    rescue JSON::ParserError => e
      return { error: "Failed to parse JSON output: #{e.message}" }
    end

  end
end
