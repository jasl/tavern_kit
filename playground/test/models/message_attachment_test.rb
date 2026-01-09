# frozen_string_literal: true

require "test_helper"

class MessageAttachmentTest < ActiveSupport::TestCase
  setup do
    @user = users(:admin)
    @space = Spaces::Playground.create!(name: "Attachment Test", owner: @user)
    @membership = @space.space_memberships.create!(user: @user, kind: "human", participation: "active", status: "active")
    @conversation = @space.conversations.create!(title: "Test")
    @message = @conversation.messages.create!(space_membership: @membership, content: "Test message", role: "user")

    # Create a test blob
    @blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("test image content"),
      filename: "test.png",
      content_type: "image/png"
    )
  end

  teardown do
    @space.destroy!
  end

  test "creates attachment with blob" do
    attachment = @message.message_attachments.create!(
      blob: @blob,
      name: "screenshot",
      kind: "image"
    )

    assert attachment.persisted?
    assert_equal @blob.id, attachment.blob_id
    assert_equal "screenshot", attachment.name
    assert_equal "image", attachment.kind
  end

  test "find_or_create_for_blob returns existing attachment" do
    attachment1 = MessageAttachment.find_or_create_for_blob(@message, @blob, name: "first")
    attachment2 = MessageAttachment.find_or_create_for_blob(@message, @blob, name: "second")

    assert_equal attachment1.id, attachment2.id
  end

  test "detect_kind_from_content_type identifies image" do
    assert_equal "image", MessageAttachment.detect_kind_from_content_type("image/png")
    assert_equal "image", MessageAttachment.detect_kind_from_content_type("image/jpeg")
  end

  test "detect_kind_from_content_type identifies audio" do
    assert_equal "audio", MessageAttachment.detect_kind_from_content_type("audio/mp3")
    assert_equal "audio", MessageAttachment.detect_kind_from_content_type("audio/wav")
  end

  test "detect_kind_from_content_type identifies video" do
    assert_equal "video", MessageAttachment.detect_kind_from_content_type("video/mp4")
  end

  test "detect_kind_from_content_type defaults to file" do
    assert_equal "file", MessageAttachment.detect_kind_from_content_type("application/pdf")
    assert_equal "file", MessageAttachment.detect_kind_from_content_type("text/plain")
  end

  test "image? returns true for image attachments" do
    attachment = @message.message_attachments.create!(blob: @blob, kind: "image")
    assert attachment.image?
    refute attachment.file?
  end

  test "content_reference returns attachment URI" do
    attachment = @message.message_attachments.create!(blob: @blob, kind: "image")
    assert_equal "attachment://#{attachment.id}", attachment.content_reference
  end

  test "blob_reference returns blob checksum URI" do
    attachment = @message.message_attachments.create!(blob: @blob, kind: "image")
    assert_equal "blob://#{@blob.checksum}", attachment.blob_reference
  end

  test "message.attach_blob creates attachment" do
    attachment = @message.attach_blob(@blob, name: "uploaded", kind: "image")

    assert attachment.persisted?
    assert_equal "uploaded", attachment.name
    assert_equal "image", attachment.kind
  end

  test "message.has_attachments? returns true when attachments exist" do
    refute @message.has_attachments?

    @message.message_attachments.create!(blob: @blob, kind: "image")

    assert @message.has_attachments?
  end

  test "message.images returns only image attachments" do
    image_blob = @blob
    file_blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new("pdf content"),
      filename: "doc.pdf",
      content_type: "application/pdf"
    )

    @message.message_attachments.create!(blob: image_blob, kind: "image")
    @message.message_attachments.create!(blob: file_blob, kind: "file")

    assert_equal 1, @message.images.count
    assert_equal 1, @message.files.count
  end
end
