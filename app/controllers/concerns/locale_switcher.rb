# frozen_string_literal: true

# This module is responsible for language switching
module LocaleSwitcher
  extend ActiveSupport::Concern
 
  SUPPORTED_LOCALES = %i[en es].freeze

  included do
    around_action :switch_locale
  end

  private

  def switch_locale(&)
    locale = params[:locale].to_sym if params[:locale].present?
    locale = I18n.default_locale unless SUPPORTED_LOCALES.include?(locale)

    I18n.with_locale(locale, &)
  rescue StandardError => e
    render json: {
      error: LogLineParse.new(e).class_name,
      message: LogLineParse.new(e).class_message
    }, status: :internal_server_error
  end
end
