# frozen_string_literal: true

require "nokogiri"
require "open-uri"
require "ferrum"
require "uri"
require "net/http"

class Scrapify
  FERRUM_DEFAULT_CONFIG = {
    headless: true,
    slow_mo: 200,
    browser_options: { "no-sandbox": nil },
    timeout: 30
  }.freeze

  def initialize(url, main_tags, attributes = [], response_type = "json")
    @url = url
    @main_tags = main_tags
    @attributes = attributes
    @response_type = response_type
    validate_inputs
  end

  def simple(use_scraping: false, screen: false, slow_mo: 200)
    setup_scraping(use_scraping, screen, slow_mo)
    return { error: "Invalid URL" } unless check_url

    doc = fetch_and_parse_content
    return { error: "The tag '#{@main_tags}' does not exist" } unless tag_exists?(doc, @main_tags)

    sub_content = doc.css(@main_tags)
    data = process_single_content(sub_content.first)
    return { error: "No content found" } if data.nil?

    data_response(data)
  end

  def list(use_scraping: false, screen: false, slow_mo: 200)
    setup_scraping(use_scraping, screen, slow_mo)
    return { error: "Invalid URL" } unless check_url

    doc = fetch_and_parse_content
    return { error: "The tag '#{@main_tags}' does not exist" } unless tag_exists?(doc, @main_tags)

    sub_content = doc.css(@main_tags)
    data = sub_content.map { |content| process_single_content(content) }.compact

    data_response(data)
  end

  def full(use_scraping: false, screen: false, slow_mo: 200)
    setup_scraping(use_scraping, screen, slow_mo)
    return { error: "Invalid URL" } unless check_url

    doc = fetch_and_parse_content
    return { error: "The tag '#{@main_tags}' does not exist" } unless tag_exists?(doc, @main_tags)

    sub_content = doc.css(@main_tags)
    data = sub_content.map do |content|
      content_data = process_single_content(content)
      next unless content_data

      # Si necesitas scrapear URLs internas (como en el método original)
      if content_data["url"]
        additional_info = simple_additional_info(content_data["url"])
        content_data.merge!(additional_info) if additional_info.is_a?(Hash) && !additional_info[:error]
      end
      content_data
    end.compact

    data_response(data)
  end

  def scrapings(use_scraping: true, screen: false, slow_mo: 200)
    setup_scraping(use_scraping, screen, slow_mo)
    return { error: "Invalid URL" } unless check_url

    doc = fetch_and_parse_content
    return { error: "The tag '#{@main_tags}' does not exist" } unless tag_exists?(doc, @main_tags)

    sub_content = doc.css(@main_tags)
    data = sub_content.map { |content| process_single_content(content) }.compact

    data_response(data)
  end

  def html(use_scraping: true, screen: false, slow_mo: 200)
    setup_scraping(use_scraping, screen, slow_mo)
    return { error: "Invalid URL" } unless check_url

    doc = fetch_and_parse_content
    return { error: "The tag '#{@main_tags}' does not exist" } unless tag_exists?(doc, @main_tags)

    sub_content = doc.css(@main_tags)
    sub_content.to_html
  end

  private

  def setup_scraping(use_scraping, screen, slow_mo)
    @use_scraping = use_scraping
    @screenshots = screen
    @slow_mo = slow_mo
  end

  def validate_inputs
    raise ArgumentError, "URL is required" if @url.nil? || @url.empty?
    raise ArgumentError, "Main tags are required" if @main_tags.nil? || @main_tags.empty?
    raise ArgumentError, "Attributes must be an array" unless @attributes.is_a?(Array)
    raise ArgumentError, "Response type must be a string" unless @response_type.is_a?(String)
  end

  def check_url
    uri = URI.parse(@url)
    uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
  rescue URI::InvalidURIError
    false
  end

  def fetch_and_parse_content
    data = Rails.cache.read(@url)
    if data.nil?
      data = fetch_html_from_url
      Rails.cache.write(@url, data, expires_in: 5.minutes) if data
    end
    parse_content(data)
  end

  def fetch_html_from_url
    if @use_scraping
      Rails.logger.debug "Fetching content with Ferrum for #{@url}"
      scraping
    else
      Rails.logger.debug "Fetching content with Net::HTTP for #{@url}"
      uri = URI(@url)
      response = Net::HTTP.get_response(uri)
      return unless response.is_a?(Net::HTTPSuccess)

      response.body
    end
  rescue StandardError => e
    Rails.logger.error "Error fetching URL #{@url}: #{e.message}"
    nil
  end

  def scraping
    browser = Ferrum::Browser.new(FERRUM_DEFAULT_CONFIG.merge(slow_mo: @slow_mo))
    browser.go_to(@url)
    browser.wait_for_selector(@main_tags, timeout: 10) rescue nil # Esperar a que el contenido esté disponible

    screenshot_data = browser.screenshot if @screenshots
    response = browser.body

    if @screenshots && screenshot_data
      screenshot = ActiveStorage::Blob.create_and_upload!(
        io: StringIO.new(screenshot_data),
        filename: "screenshot_#{Time.now.to_i}.png",
        content_type: "image/png"
      )
      response = { html: response, screenshot_key: screenshot.key }
    end

    browser.quit
    response
  rescue StandardError => e
    Rails.logger.error "Ferrum error for #{@url}: #{e.message}"
    nil
  end

  def parse_content(data)
    return unless data

    Nokogiri::HTML(data.is_a?(Hash) ? data[:html] : data)
  end

  def tag_exists?(doc, tags)
    tags.split.any? { |tag| doc.at_css(tag) }
  end

  def process_single_content(content)
    return unless content

    @attributes.each_with_object({}) do |attribute, hash|
      name = attribute["name"] || attribute[:name]
      content_selector = attribute["content"] || attribute[:content]
      actions = attribute["actions"] || attribute[:actions] || []

      current_content = content.css(content_selector)
      return unless current_content.any?

      response_action = if actions.empty?
                          current_content.text.strip
      else
                          action_values(actions, current_content)
      end

      hash[name] = response_action if response_action
    end
  end

  def action_values(actions, attribute_content)
    response = attribute_content.text.strip
    actions.each do |action|
      response = process_action(action, response, attribute_content)
      break if response.nil?
    end
    response
  end

  def process_action(action, response, attribute_content)
    type = action["type"] || action[:type]
    value = action["value"] || action[:value] || ""
    new_value = action["new"] || action[:new] || ""

    case type
    when "delete"
      response.delete(value) if response
    when "gsub"
      response.gsub(value, new_value) if response
    when "split"
      response.split(value)
    when "full_attr"
      include_http(attribute_content.attr(value)&.text)
    when "attr"
      attribute_content.attr(value)&.text
    when "html"
      attribute_content.to_html
    when "strip"
      response&.strip
    when "array"
      if value.present?
        attribute_content[value.to_i]&.text
      else
        response.to_s.split("\n").map(&:split).reject(&:empty?)
      end
    when "clear"
      response.to_s.split("\n").map(&:split).reject(&:empty?)
    when "delete_att"
      response&.delete(value)
    when "attrs"
      attrs_list(action, attribute_content)
    else
      response
    end
  rescue StandardError => e
    Rails.logger.error "Error processing action #{type}: #{e.message}"
    nil
  end

  def attrs_list(action, attribute_content)
    value = action["value"] || action[:value]
    attr_list = attribute_content.map do |elem|
      elem.attr(value)&.text&.strip
    end.compact
    action["unique"] || action[:unique] ? attr_list.uniq : attr_list
  end

  def include_http(value)
    return unless value

    if value.start_with?("http://", "https://")
      value
    else
      "https://#{get_domain_name}#{value}"
    end
  end

  def get_domain_name
    URI.parse(@url).host
  rescue URI::InvalidURIError
    nil
  end

  def data_response(data)
    case @response_type
    when "plain", "html"
      data.to_s
    else
      data
    end
  end

  def simple_additional_info(link)
    scrapify_instance = self.class.new(link, @main_tags, @attributes, @response_type)
    scrapify_instance.simple
  end
end
