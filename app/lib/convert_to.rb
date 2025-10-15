# frozen_string_literal: true

require 'csv'
require 'json'
require 'roo'

class ConvertTo
  def self.csv_to_json(csv_file)
    data = read_csv_data(csv_file)
    json_data = convert_to_json(data)
    write_json_file('name.json', JSON.parse(json_data))

    json_data
  end

  def self.csv_to_jsonl(csv_file)
    data = read_csv_data(csv_file)
    json_data = convert_to_json(data)
    write_json_file('name.jsonl', JSON.parse(json_data))

    json_data
  end

  # no usar
  def self.csv_json(file)
    extension = File.extname(file)
    if file.is_a?(String) && file.start_with?('http')
      archivo_json = file.match(%r{/([^/]+)$})[1].sub(/\..+$/, '.json')
      # file = URI.open(file).read
      file = URI.open(file)
    else
      archivo_json = file.original_filename.sub(/\..+$/, '.json')
    end

    # json_files = [] # whatch later
    # all_json_data = [] # whatch later

    case extension
    when '.csv'
      data = read_csv_data(file)
      json_data = convert_to_json(data)
      write_json_file(archivo_json, JSON.parse(json_data))
      json_data
    when '.xlsx'
      data = Roo::Excelx.new(file)
      if data.sheets.length == 1
        headers = data.row(1)
        json_data = (2..data.last_row).map { |i| headers.zip(data.row(i)).to_h }.to_json
        write_json_file(archivo_json, JSON.parse(json_data))
        json_data
      else
        json_data = []
        data.sheets.each do |sheet|
          archivo_json = "#{sheet}.json"
          data.default_sheet = sheet
          headers = data.row(1)
          sheet_data = (2..data.last_row).map { |i| headers.zip(data.row(i)).to_h }
          json_data.concat(sheet_data)
          write_json_file(archivo_json, JSON.parse(sheet_data.to_json))
          # json_files << archivo_json # whatch later
          # all_json_data.concat(sheet_data) # whatch later
        end
        # all_json_data.to_json
        json_data.to_json
      end
    else
      raise 'Formato de archivo no compatible. Se esperaba CSV o XLSX.'
    end

    { json_data:, archivo_json: }
    # { json_data: json_data || all_json_data, archivo_json: json_files || archivo_json } # whatch later
  end


  def self.acta_csv_json(file)
    extension = File.extname(file)
    if file.is_a?(String) && file.start_with?('http')
      archivo_json = file.match(%r{/([^/]+)$})[1].sub(/\..+$/, '.json')
      # file = URI.open(file).read
      file = URI.open(file)
    else
      archivo_json = file.original_filename.sub(/\..+$/, '.json')
    end

    # json_files = [] # whatch later
    # all_json_data = [] # whatch later

    case extension
    when '.csv'
      data = read_csv_data(file)
      json_data = convert_to_json(data)
      write_json_file(archivo_json, JSON.parse(json_data))
      json_data
    when '.xlsx'
      data = Roo::Excelx.new(file)
      if data.sheets.length == 1
        headers = data.row(15)
        json_data = (16..data.last_row).map { |i| headers.zip(data.row(i)).to_h }.to_json

        info_Acta = {
          data_start: data.row(9).last,
          acta_number: data.row(10).first,
          start_time: data.row(10).last,
          end_time: data.row(11).last,
          objetive: data.row(12).first,
          link: data.row(12).last
        }

        write_json_file(archivo_json, JSON.parse(json_data))
        json_data
      else
        json_data = []
        data.sheets.each do |sheet|
          archivo_json = "#{sheet}.json"
          data.default_sheet = sheet
          headers = data.row(14)
          sheet_data = (2..data.last_row).mapheaders { |i| headers.zip(data.row(i)).to_h }
          json_data.concat(sheet_data)
          write_json_file(archivo_json, JSON.parse(sheet_data.to_json))
          # json_files << archivo_json # whatch later
          # all_json_data.concat(sheet_data) # whatch later
        end
        # all_json_data.to_json
        json_data.to_json
      end
    else
      raise 'Formato de archivo no compatible. Se esperaba CSV o XLSX.'
    end

    { json_data:, archivo_json: , info_Acta:}
    # { json_data: json_data || all_json_data, archivo_json: json_files || archivo_json } # whatch later
  end

  def self.jsonl_to_json(file_path)
    file = File.read(file_path)
    json_data = JSON.parse(file)
    write_json_file('name.json', json_data)

    json_data
  end

  def self.json_to_jsonl(file_path)
    json_data = JSON.parse(File.read(file_path))
    create_jsonl_file('name.jsonl', json_data)
    json_data
  end

  def self.json_to_csv(json_file, csv_file)
    json_data = JSON.parse(File.read(json_file))
    generate_csv_file(csv_file, json_data)
  end

  def self.jsonl_to_csv(jsonl_file, csv_file)
    json_data = JSON.parse(File.read(jsonl_file))
    generate_csv_file(csv_file, json_data)
  end

  def self.generate_csv_file(csv_file, json_data)
    CSV.open(csv_file, 'w') do |csv|
      csv << json_data.first.keys

      json_data.each do |item|
        csv << item.values
      end
    end

    Rails.logger.debug { "CSV file '#{csv_file}' created successfully." }
  end

  def self.read_csv_data(csv_file)
    data = []

    # Leer el archivo CSV
    CSV.foreach(csv_file, headers: true) do |row|
      data.push(row.to_h)
    end

    data
  end

  def self.convert_to_json(data)
    data.to_json
  end

  def self.create_jsonl_file(file_name, data)
    File.open(file_name, 'w') do |file|
      data.each do |entry|
        file.puts(entry.to_json)
      end
    end

    Rails.logger.debug { "File '#{file_name}' created successfully." }
  end

  def self.write_json_file(file_name, json_data)
    File.open(file_name, 'w') do |file|
      file.puts JSON.pretty_generate(json_data)
    end
  end
end

# OLD
# class ConvertTo
#   def self.read_csv_data(csv_file)
#     data = []

#     # Leer el archivo CSV
#     CSV.foreach(csv_file, headers: true) do |row|
#       data.push(row.to_h)
#     end

#     data
#   end

#   def self.convert_to_json(data)
#     data.to_json
#   end

#   def self.write_json_file(file_name, json_data)
#     File.open(file_name, 'w') do |file|
#       file.puts JSON.pretty_generate(json_data)
#     end
#   end

#   def self.csv_to_json(csv_file)
#     data = read_csv_data(csv_file)
#     json_data = convert_to_json(data)
#     write_json_file('name.json', json_data)

#     json_data
#   end

#   def self.csv_to_jsonl(csv_file)
#     data = read_csv_data(csv_file)
#     json_data = convert_to_json(data)
#     write_json_file('name.jsonl', json_data)

#     json_data
#   end

#   def self.csv_json(file_path)
#     extension = File.extname(file_path)
#     case extension
#     when '.csv'
#       data = read_csv_data(file_path)
#       json_data = convert_to_json(data)
#       write_json_file('name.json', json_data)

#       json_data
#     when '.xlsx'
#       data = Roo::Excelx.new(file_path)
#       headers = data.row(1)
#       json_data = (2..data.last_row).map { |i| Hash[headers.zip(data.row(i))] }.to_json
#       write_json_file('name.json', json_data)

#       json_data
#     else
#       raise 'Formato de archivo no compatible. Se esperaba CSV o XLSX.'
#     end
#   end

#   def self.jsonl_to_json(file_path)
#     file = File.read(file_path)
#     json_data = JSON.parse(file)
#     write_json_file('name.json', json_data)

#     json_data
#   end
# end

#   def self.json_to_jsonl(file_path)
#     file = File.read(file_path)
#     json_data = JSON.parse(file)
#     create_json_file('names.jsonl', json_data)
#     return json_data
#   end

#   def self.json_to_csv(json_data, csv_file)
#     json_data = JSON.parse(File.read(json_data))

#     # Genera el texto para reponder
#     csv_data = CSV.generate do |csv|
#       csv << json_data.first.keys

#       json_data.each do |item|
#         csv << item.values
#       end
#     end

#     # Escribe el archivo
#     CSV.open(csv_file, "w") do |csv|
#       csv << json_data.first.keys

#       json_data.each do |item|
#         csv << item.values
#       end
#     end

#     csv_data
#   end

#   def self.jsonl_to_csv(json_data, csv_file)
#     json_data = JSON.parse(File.read(json_data))

#     # Genera el texto para reponder
#     csv_data = CSV.generate do |csv|
#       csv << json_data.first.keys

#       json_data.each do |item|
#         csv << item.values
#       end
#     end

#     # Escribe el archivo
#     CSV.open(csv_file, "w") do |csv|
#       csv << json_data.first.keys

#       json_data.each do |item|
#         csv << item.values
#       end
#     end

#     csv_data
#   end

#   def self.create_json_file(file_name, data)
#     require 'json'

#     File.open(file_name, "w") do |file|
#       file.write(data.to_json)
#     end

#     puts "File '#{file_name}' created successfully."
#   end
# end
