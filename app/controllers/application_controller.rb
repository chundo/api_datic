class ApplicationController < ActionController::API
    include LocaleSwitcher
    include FileProcessingConcern

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
