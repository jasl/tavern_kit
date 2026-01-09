# frozen_string_literal: true

# MessageAttachment links a Message to an ActiveStorage::Blob.
#
# This model enables attaching files (images, documents, audio, video) to messages.
# Multiple messages can share the same blob for efficient storage (e.g., when forking).
#
# Attachment kinds:
# - image: photos, screenshots, AI-generated images
# - file: documents, PDFs, spreadsheets
# - audio: voice messages, sound files
# - video: video clips
#
# Content referencing (future):
# Message content can reference attachments using:
# - Markdown: ![alt](attachment://uuid) or ![alt](blob://checksum)
# - Placeholder: {{file:uuid}}
#
# @example Attach an image to a message
#   blob = ActiveStorage::Blob.create_and_upload!(
#     io: File.open("image.png"),
#     filename: "image.png",
#     content_type: "image/png"
#   )
#   message.message_attachments.create!(blob: blob, name: "screenshot", kind: "image")
#
# @example Find or reuse existing blob
#   attachment = MessageAttachment.find_or_create_for_blob(message, blob, name: "doc", kind: "file")
#
class MessageAttachment < ApplicationRecord
  # Attachment kinds
  KINDS = %w[image file audio video].freeze

  # Associations
  belongs_to :message
  belongs_to :blob, class_name: "ActiveStorage::Blob"

  # Validations
  validates :kind, inclusion: { in: KINDS }
  validates :blob_id, uniqueness: { scope: :message_id, message: "already attached to this message" }

  # Scopes
  scope :ordered, -> { order(:position, :created_at) }
  scope :images, -> { where(kind: "image") }
  scope :files, -> { where(kind: "file") }
  scope :audio, -> { where(kind: "audio") }
  scope :video, -> { where(kind: "video") }

  # Delegate common blob attributes
  delegate :filename, :content_type, :byte_size, :checksum, to: :blob
  delegate :url, :download, to: :blob, prefix: true

  # Find or create an attachment for a blob on a message.
  # If the blob is already attached, returns the existing attachment.
  #
  # @param message [Message] the message to attach to
  # @param blob [ActiveStorage::Blob] the blob to attach
  # @param name [String, nil] display name
  # @param kind [String] attachment kind (image, file, audio, video)
  # @param position [Integer] ordering position
  # @param metadata [Hash] additional metadata
  # @return [MessageAttachment] the found or created attachment
  def self.find_or_create_for_blob(message, blob, name: nil, kind: nil, position: 0, metadata: {})
    kind ||= detect_kind_from_content_type(blob.content_type)

    find_or_create_by!(message: message, blob: blob) do |attachment|
      attachment.name = name || blob.filename.to_s
      attachment.kind = kind
      attachment.position = position
      attachment.metadata = metadata
    end
  end

  # Detect attachment kind from content type.
  #
  # @param content_type [String] MIME type
  # @return [String] attachment kind
  def self.detect_kind_from_content_type(content_type)
    case content_type.to_s
    when %r{^image/}
      "image"
    when %r{^audio/}
      "audio"
    when %r{^video/}
      "video"
    else
      "file"
    end
  end

  # Check if this is an image attachment.
  #
  # @return [Boolean]
  def image?
    kind == "image"
  end

  # Check if this is a file attachment.
  #
  # @return [Boolean]
  def file?
    kind == "file"
  end

  # Check if this is an audio attachment.
  #
  # @return [Boolean]
  def audio?
    kind == "audio"
  end

  # Check if this is a video attachment.
  #
  # @return [Boolean]
  def video?
    kind == "video"
  end

  # Get a reference string for use in message content.
  # Can be used in Markdown: ![alt](attachment://uuid)
  #
  # @return [String] attachment reference URI
  def content_reference
    "attachment://#{id}"
  end

  # Get a blob reference string (content-addressable).
  # Can be used in Markdown: ![alt](blob://checksum)
  #
  # @return [String] blob reference URI
  def blob_reference
    "blob://#{blob.checksum}"
  end
end
