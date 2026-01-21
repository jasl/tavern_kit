# frozen_string_literal: true

require "test_helper"

module CharacterImport
  class UploadEnqueuerTest < ActiveSupport::TestCase
    setup do
      @user = users(:admin)
      clear_enqueued_jobs
    end

    test "returns no_file when file is nil" do
      assert_no_difference ["Character.count", "CharacterUpload.count"] do
        assert_no_enqueued_jobs do
          callback = nil
          result = UploadEnqueuer.new(
            user: @user,
            file: nil,
            on_error: ->(error_code, error) { callback = [error_code, error] }
          ).execute

          assert_not result.success?
          assert_equal :no_file, result.error_code
          assert_equal [:no_file, "No file provided"], callback
        end
      end
    end

    test "returns unsupported_format when extension is not supported" do
      callback = nil
      file = build_uploaded_file(filename: "notes.txt", content_type: "text/plain", content: "hi")

      assert_no_difference ["Character.count", "CharacterUpload.count"] do
        assert_no_enqueued_jobs do
          result = UploadEnqueuer.new(
            user: @user,
            file: file,
            on_error: ->(error_code, error) { callback = [error_code, error] }
          ).execute

          assert_not result.success?
          assert_equal :unsupported_format, result.error_code
          assert_equal [:unsupported_format, "Unsupported file format"], callback
        end
      end
    ensure
      file&.tempfile&.close!
    end

    test "creates placeholder character + upload and enqueues import job" do
      events = []
      file = build_uploaded_file(filename: "my_character.json", content_type: "application/json", content: "{}")

      result = nil

      assert_difference ["Character.count", "CharacterUpload.count"], 1 do
        result = UploadEnqueuer.new(
          user: @user,
          file: file,
          on_created: ->(character, upload) { events << [:created, character, upload] },
          on_enqueued: ->(character, upload) { events << [:enqueued, character, upload] }
        ).execute
      end

      assert result.success?
      assert_equal "pending", result.character.status
      assert_nil result.character.user
      assert_equal "my_character", result.character.name

      assert_equal "pending", result.upload.status
      assert_equal result.character.id, result.upload.character_id
      assert_equal @user.id, result.upload.user_id
      assert_equal "my_character.json", result.upload.filename
      assert result.upload.file.attached?

      job = enqueued_jobs.find { |j| j[:job] == CharacterImportJob }
      assert_not_nil job, "Expected CharacterImportJob to be enqueued"
      assert_equal [result.upload.id], job[:args]

      assert_equal %i[created enqueued], events.map(&:first)
      assert_equal result.character, events.first[1]
      assert_equal result.upload, events.first[2]
    ensure
      file&.tempfile&.close!
    end

    private

    def build_uploaded_file(filename:, content_type:, content:)
      ext = File.extname(filename)
      tempfile = Tempfile.new(["upload", ext])
      tempfile.binmode
      tempfile.write(content)
      tempfile.rewind

      ActionDispatch::Http::UploadedFile.new(
        tempfile: tempfile,
        filename: filename,
        type: content_type
      )
    end
  end
end
