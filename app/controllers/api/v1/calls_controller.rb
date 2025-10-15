# frozen_string_literal: true

module Api
  module V1
    class CallsController < ApplicationController
      # skip_before_action :verify_authenticity_token, only: [ :incoming ]

      def incoming
        twiml = Twilio::TwiML::VoiceResponse.new do |r|
          r.say(message: "Bienvenido a tu momento de paz espiritual. Que la gracia de Dios est\u00E9 contigo.", language: "es-MX")
          r.pause(length: 1)
          r.say(message: "Estoy aqu\u00ED para acompa\u00F1arte y compartir la palabra de Dios. \u00BFEn qu\u00E9 puedo guiarte hoy?", language: "es-MX")
          r.connect do |c|
            c.stream(url: "wss://#{request.host_with_port}/media-stream")
          end
        end

        render xml: twiml.to_s
      end

      def download_recording
        call_sid = params[:call_sid]
        file_path = Rails.root.join("tmp", "recording_#{call_sid}.raw").to_s
        unless File.exist?(file_path)
          return render json: { error: "Archivo de grabaci\u00F3n no encontrado." }, status: :not_found
        end

        send_file(
          file_path,
          type: "audio/basic",
          disposition: "attachment",
          filename: "recording_#{call_sid}.raw"
        )
      end
    end
  end
end
