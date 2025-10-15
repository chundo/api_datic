# frozen_string_literal: true

require "uri"
require "net/http"
require "json"

class FinanceServices
  # This class is responsible for making requests to the Ideardev API.
  # It handles GET and POST requests, including setting the necessary headers and authentication.

  # Sends a request to the Ideardev API.
  #
  # @param url [String] The endpoint URL to send the request to (can include query parameters).
  # @param method [String] The HTTP method to use (default: 'get').
  # @param body [Hash, nil] The request body (default: nil).
  #
  # @return [Hash] The parsed JSON response from the API, or raises an error on failure.
  def self.request(url, method = "get", body = nil)
    token = ENV.fetch("IDEAR_TOKEN", nil)
    base_url = url.include?("start") || url.include?("run") ? ENV.fetch("IDEAR_URL_SCR", nil) : ENV.fetch("IDEAR_URL", nil)

    # Parse the URL to handle existing query parameters
    uri = URI.parse(url.start_with?("http") ? url : "#{base_url}#{url}")

    # Get existing query parameters or initialize empty hash
    query_params = uri.query ? URI.decode_www_form(uri.query).to_h : {}

    # Add access token to query parameters
    # query_params["access_token"] = token

    # Reconstruct query string
    uri.query = URI.encode_www_form(query_params)

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = case method.downcase
    when "get"
      Net::HTTP::Get.new(uri)
    when "post"
      Net::HTTP::Post.new(uri)
    else
      raise ArgumentError, "Unsupported HTTP method: #{method}"
    end

    request["accept"] = "application/json"

    if body
      request["content-type"] = "application/json"
      request.body = body.is_a?(Hash) ? JSON.generate(body) : body.to_s
    end

    response = http.request(request)

    # Parse and return JSON response
    JSON.parse(response.read_body)
  rescue Net::HTTPExceptions => e
    raise "HTTP Request failed: #{e.message}"
  rescue JSON::ParserError
    raise "Invalid JSON response from API"
  end

  # Fetches data from the API using a GET request.
  #
  # @param url [String] The endpoint URL to fetch data from.
  # @return [Hash] The parsed JSON response.
  def self.get_data(url)
    request(url)
  end

  # Sends data to the API using a POST request.
  #
  # @param url [String] The endpoint URL to send data to.
  # @param body [Hash] The data to send.
  # @return [Hash] The parsed JSON response.
  def self.set_data(url, body)
    request(url, "post", body)
  end
end
