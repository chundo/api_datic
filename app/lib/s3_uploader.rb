# frozen_string_literal: true

# app/services/s3_uploader.rb
require 'aws-sdk-s3'

class S3Uploader
  class UploadError < StandardError; end

  def initialize(bucket_name = ENV['S3_BUCKET'] || 'aca-demo-actas', region = ENV['AWS_REGION'] || 'us-east-1')
    @bucket_name = bucket_name
    @region = region

    # Configurar el cliente S3 usando las credenciales por defecto
    # AWS SDK buscará credenciales en:
    # 1. Variables de entorno (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
    # 2. Archivo ~/.aws/credentials
    # 3. Rol de IAM (si estás en EC2, ECS, etc.)
    # @s3 = Aws::S3::Client.new(region: @region)
    @s3 = Aws::S3::Client.new(
      access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
      region: 'us-easst-1'
    )

    validate_configuration
  end

  def upload_file(file, file_name = nil, acl: 'private')
    # Si file es un string, abrir el archivo desde el path
    if file.is_a?(String)
      raise UploadError, "Archivo no encontrado: #{file}" unless File.exist?(file)
      file = File.open(file, 'rb')
      close_file = true
    end

    validate_file(file)
    object_key = generate_object_key(file, file_name)

    begin
      response = @s3.put_object(
        bucket: @bucket_name,
        key: object_key,
        body: file,
        content_type: determine_content_type(file),
        acl: acl # 'private' o 'public-read'
      )

      # Generar una URL para el archivo
      url = if acl == 'public-read'
              "https://#{@bucket_name}.s3.#{@region}.amazonaws.com/#{object_key}"
            else
              # Generar una URL presignada para archivos privados (expira en 1 hora)
              signer = Aws::S3::Presigner.new(client: @s3)
              signer.presigned_url(
                :get_object,
                bucket: @bucket_name,
                key: object_key,
                expires_in: 3600 # 1 hora
              )
            end

      {
        success: true,
        url: url,
        etag: response.etag,
        object_key: object_key
      }
    rescue Aws::S3::Errors::ServiceError => e
      raise UploadError, "Error subiendo archivo a S3: #{e.message}"
    ensure
      file.rewind if file.respond_to?(:rewind)
      file.close if close_file && file.respond_to?(:close)
    end
  end

  private

  def validate_configuration
    raise UploadError, 'Bucket no configurado' if @bucket_name.blank?
    raise UploadError, 'Región no configurada' if @region.blank?

    # Verificar que las credenciales estén configuradas
    begin
      @s3.head_bucket(bucket: @bucket_name)
    rescue Aws::S3::Errors::Forbidden
      raise UploadError, "Acceso denegado al bucket #{@bucket_name}. Verifica las credenciales y permisos."
    rescue Aws::S3::Errors::NotFound
      raise UploadError, "El bucket #{@bucket_name} no existe."
    rescue Aws::S3::Errors::ServiceError => e
      raise UploadError, "Error al validar la configuración de S3: #{e.message}"
    end
  end

  def validate_file(file)
    return if valid_file?(file)

    raise UploadError, 'Archivo inválido o vacío'
  end

  def valid_file?(file)
    file.present? &&
      file.respond_to?(:read) &&
      file.size.positive?
  rescue StandardError
    false
  end

  def determine_content_type(file)
    # Intentar determinar el tipo de contenido si no está definido
    content_type = file.content_type if file.respond_to?(:content_type)
    content_type ||= MIME::Types.type_for(file.path).first&.content_type if file.respond_to?(:path)
    content_type || 'application/octet-stream'
  end

  def generate_object_key(file, custom_name)
    timestamp = Time.zone.now.strftime('%Y%m%d_%H%M%S')
    original_name = if file.is_a?(String)
                      File.basename(file)
                    else
                      file.original_filename if file.respond_to?(:original_filename)
                    end

    # Usar el nombre personalizado si se proporciona, de lo contrario usar el nombre original
    base_name = custom_name || original_name || 'unnamed_file'
    "#{timestamp}_#{SecureRandom.hex(4)}_#{base_name}".parameterize
  end
end