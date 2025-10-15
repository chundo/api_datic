# frozen_string_literal: true

class UserMailer < ApplicationMailer
  def send_code_verify(user)
    code = user.pin
    @user = user
    mail(to: @user.email, subject: I18n.t("sign_up.verification_code"),
         body: %(#{I18n.t('sign_up.verification_code_body')} #{code}))
  end

  def send_document(document)
    attachments[document[:document][:file_path]] = File.read(document[:document][:file_path])
    mail(
      to: document[:email],
      subject: document[:title],
      body: "Archivo generado automaticamente por ai, valide el documento y cambie de azul a negro"
    )
  end

  def send_error(document)
    mail(
      to: document[:email],
      subject: document[:title],
      body: document[:body],
    )
  end
end
