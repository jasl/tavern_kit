# frozen_string_literal: true

require "test_helper"

module LorebookImport
  class UploadEnqueuerTest < ActiveSupport::TestCase
    setup do
      @user = users(:admin)
      clear_enqueued_jobs
    end

    test "returns no_file when file is nil" do
      assert_no_difference ["Lorebook.count", "LorebookUpload.count"] do
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

      assert_no_difference ["Lorebook.count", "LorebookUpload.count"] do
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

    test "creates placeholder lorebook + upload and enqueues import job" do
      events = []
      file = build_uploaded_file(filename: "my_lorebook.json", content_type: "application/json", content: "{}")

      result = nil

      assert_difference ["Lorebook.count", "LorebookUpload.count"], 1 do
        result = UploadEnqueuer.new(
          user: @user,
          file: file,
          owner: @user,
          visibility: "private",
          name_override: "My Lorebook",
          on_created: ->(lorebook, upload) { events << [:created, lorebook, upload] },
          on_enqueued: ->(lorebook, upload) { events << [:enqueued, lorebook, upload] }
        ).execute
      end

      assert result.success?
      assert_equal "pending", result.lorebook.status
      assert_equal @user.id, result.lorebook.user_id
      assert_equal "private", result.lorebook.visibility
      assert_equal "My Lorebook", result.lorebook.name

      assert_equal "pending", result.upload.status
      assert_equal result.lorebook.id, result.upload.lorebook_id
      assert_equal @user.id, result.upload.user_id
      assert_equal "my_lorebook.json", result.upload.filename
      assert result.upload.file.attached?

      job = enqueued_jobs.find { |j| j[:job] == LorebookImportJob }
      assert_not_nil job, "Expected LorebookImportJob to be enqueued"
      assert_equal [result.upload.id], job[:args]

      assert_equal %i[created enqueued], events.map(&:first)
      assert_equal result.lorebook, events.first[1]
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
