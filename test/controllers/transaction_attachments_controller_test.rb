require "test_helper"

class TransactionAttachmentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @entry = entries(:transaction)
    @transaction = @entry.transaction
    @family = @transaction.entry.account.family
  end

  test "create attaches file and uploads to vector store when extension supported" do
    file = Rack::Test::UploadedFile.new(
      StringIO.new("receipt content"),
      "text/plain",
      true,
      filename: "receipt.txt"
    )

    family_doc = family_documents(:tax_return)
    @family.expects(:upload_document).with do |kwargs|
      kwargs[:filename] == "receipt.txt" &&
        kwargs[:metadata]["source"] == "transaction_attachment" &&
        kwargs[:metadata]["transaction_id"] == @transaction.id.to_s &&
        kwargs[:metadata]["attachment_id"].present?
    end.returns(family_doc).once

    assert_difference "@transaction.attachments.count", 1 do
      post transaction_attachments_path(@transaction), params: { file: file }
    end

    assert_redirected_to transaction_path(@entry)
    assert_equal I18n.t("transaction_attachments.create.success"), flash[:notice]
  end

  test "create redirects with alert when no file" do
    assert_no_difference "@transaction.attachments.count" do
      post transaction_attachments_path(@transaction), params: {}
    end

    assert_redirected_to transaction_path(@entry)
    assert_equal I18n.t("transaction_attachments.create.missing_file"), flash[:alert]
  end

  test "destroy purges attachment and removes from vector store" do
    @transaction.attachments.attach(
      io: StringIO.new("x"),
      filename: "note.txt",
      content_type: "text/plain"
    )
    attachment = @transaction.attachments.last

    family_doc = OpenStruct.new(id: "doc-1", provider_file_id: "file-1")
    @family.expects(:find_family_document_for_transaction_attachment)
      .with(transaction_id: @transaction.id, attachment_id: attachment.id)
      .returns(family_doc)
    @family.expects(:remove_document).with(family_doc).returns(true)

    assert_difference "@transaction.attachments.count", -1 do
      delete transaction_attachment_path(@transaction, attachment)
    end

    assert_redirected_to transaction_path(@entry)
    assert_equal I18n.t("transaction_attachments.destroy.success"), flash[:notice]
  end
end
