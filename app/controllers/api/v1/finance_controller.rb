# frozen_string_literal: true

module Api
  module V1
    class FinanceController < ApplicationController
      def symbol_search
        symbol = params[:symbol] || "BTC"
        data = data_symbol_search(symbol:  symbol)
        render json: data, status: :ok
      end

      def historical
        symbol = params[:symbol] || "BTC"
        limit = params[:limit] || 8
        interval = params[:interval] || nil
        data = TechnicalAnalysis.fetch_historical_data(symbol: symbol, limit: limit, interval: interval)
        render json: data, status: :ok
      end

      def rss
        symbol = params[:symbol] || "BTC"
        asset_type  = params[:asset_type] || "stock"
        rss_only = params[:rss_only] || true
        date = params[:date] || Time.now.to_i * 1000
        data = data_rss(symbol: symbol, asset_type:, rss_only:, date:)
        render json: data, status: :ok
      end

      def query_type
        query = params[:query] || "XRP"
        data = data_query_type(query: query)
        render json: data, status: :ok
      end

      def generate_signal
        query = params[:query] || "XRP"
        symbol = params[:symbol] || "XRP"
        limit = params[:limit] || 8
        interval = params[:interval] || nil
        historical = TechnicalAnalysis.fetch_historical_data(symbol: symbol, limit: limit, interval: interval)
        data = data_generate_response(query: "#{query} #{historical}")
        render json: data, status: :ok
      end

      def anality
        query = params.require(:query)
        symbol = params[:symbol]
        limit = params[:limit]
        intervals = params[:intervals]

        # # Validar parámetros
        render json: { error: "Symbol is required" }, status: :unprocessable_entity and return unless symbol.present?
        render json: { error: "Intervals must be a non-empty array" }, status: :unprocessable_entity and return unless intervals.is_a?(Array) && !intervals.empty?


        historical_data_by_interval = intervals.each_with_object({}) do |interval, result|
          # Obtener datos históricos
          begin
            data = TechnicalAnalysis.fetch_historical_data(symbol: symbol, limit: limit, interval: interval)
            result[interval] = data
          rescue StandardError => e
            result[interval] = { error: "Failed to fetch data for interval #{interval}: #{e.message}" }
          end
        end

        data = TechnicalAnalysis.analyze_market(symbol: symbol, limit: limit, interval: intervals[0])
        data.merge!(historical: historical_data_by_interval)

        handler = AiModelHandler.new({})
        response = handler.generate("#{query} #{data}", model: "openai", model_version: "gpt-4o-mini")

        render json: { data: data, response: response }, status: :ok
      end

      def main_anality
        data = TechnicalAnalysis.analyze_market
        render json: data, status: :ok
      end

      def comprehensive
        symbol = params[:symbol] || "BTC"
        data = data_comprehensive(symbol:  symbol)
        render json: data, status: :ok
      end

      private

      def data_symbol_search(symbol: "BTC")
        FinanceServices.get_data("#{Settings.technical_anality.provider3}/symbol_search?symbol=#{symbol}&source=docs")
      end

      def data_comprehensive(symbol: "BTC")
        FinanceServices.get_data("#{Settings.technical_anality.provider2}/api/comprehensive?symbol=#{symbol}")
      end

      def data_rss(symbol: "BTC", asset_type: "stock", rss_only: true, date: Time.now.to_i * 1000)
        FinanceServices.get_data("#{Settings.technical_anality.provider2}/api/rss?assetType=#{asset_type}&symbol=#{symbol}&t=#{date}&rssOnly=#{rss_only}")
      end

      def data_query_type(query: nil)
        FinanceServices.set_data("#{Settings.technical_anality.provider2}/api/query-type", { query: query })
      end

      def data_generate_response(query: nil)
        FinanceServices.set_data("#{Settings.technical_anality.provider2}/api/generate-response", { query: query })
      end

      # https://twelvedata.com/pricing
      # https://developers.binance.com/docs/binance-spot-api-docs/rest-api/market-data-endpoints
    end
  end
end
