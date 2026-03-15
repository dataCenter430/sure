# Handles file attachments on transactions and syncs them to the family vector store
# when configured, so they are searchable (e.g. by AI chat).
class TransactionAttachmentsController < ApplicationController
  before_action :set_transaction

  def create
    file = params[:file]
    unless file.present?
      redirect_back fallback_location: transaction_path_for_redirect, alert: t("transaction_attachments.create.missing_file")
      return
    end

    @transaction.attachments.attach(file)
    attachment = @transaction.attachments.last

    upload_to_vector_store(attachment)

    redirect_back fallback_location: transaction_path_for_redirect, notice: t("transaction_attachments.create.success")
  end

  def destroy
    attachment = @transaction.attachments.find(params[:id])
    remove_from_vector_store(attachment)
    attachment.purge
    redirect_back fallback_location: transaction_path_for_redirect, notice: t("transaction_attachments.destroy.success")
  end

  private

    def set_transaction
      @transaction = Current.family.transactions.find(params[:transaction_id])
    end

    def transaction_path_for_redirect
      transaction_path(@transaction.entry)
    end

    def upload_to_vector_store(attachment)
      return unless vector_store_extension?(attachment.filename.to_s)

      file_content = attachment.blob.download
      filename = attachment.filename.to_s
      metadata = {
        "source" => "transaction_attachment",
        "transaction_id" => @transaction.id.to_s,
        "attachment_id" => attachment.id.to_s
      }

      family_document = Current.family.upload_document(
        file_content: file_content,
        filename: filename,
        metadata: metadata
      )

      Rails.logger.warn("TransactionAttachmentsController: Vector store upload failed for attachment #{attachment.id}") unless family_document
    end

    def remove_from_vector_store(attachment)
      family_document = Current.family.find_family_document_for_transaction_attachment(
        transaction_id: @transaction.id,
        attachment_id: attachment.id
      )
      Current.family.remove_document(family_document) if family_document
    end

    def vector_store_extension?(filename)
      ext = File.extname(filename).downcase
      VectorStore::Base::SUPPORTED_EXTENSIONS.map(&:downcase).include?(ext)
    end
end
