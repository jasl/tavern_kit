# frozen_string_literal: true

require "test_helper"

class LorebooksControllerTest < ActionDispatch::IntegrationTest
  setup do
    clear_enqueued_jobs
    sign_in :member
  end

  test "import supports multiple files and enqueues one job per file" do
    user = users(:member)
    file1 = uploaded_fixture("lorebooks/world_one.json", content_type: "application/json")
    file2 = uploaded_fixture("lorebooks/world_two.json", content_type: "application/json")

    assert_difference ["Lorebook.count", "LorebookUpload.count"], 2 do
      assert_enqueued_jobs 2, only: LorebookImportJob do
        post import_lorebooks_url,
             params: { file: ["", file1, file2], name: "Prefix" },
             headers: { "Accept" => "text/html" }
      end
    end

    assert_redirected_to lorebooks_url
    assert_nil flash[:alert]

    created = Lorebook.order(created_at: :desc).limit(2)
    assert_equal 2, created.size
    assert created.all?(&:pending?)
    assert created.all? { |lb| lb.user_id == user.id }
    assert created.all? { |lb| lb.visibility == "private" }
    assert_includes created.map(&:name), "Prefix world_one"
    assert_includes created.map(&:name), "Prefix world_two"
  end

  test "import uses name override as-is for single file" do
    user = users(:member)
    file = uploaded_fixture("lorebooks/world_one.json", content_type: "application/json")

    assert_difference ["Lorebook.count", "LorebookUpload.count"], 1 do
      assert_enqueued_jobs 1, only: LorebookImportJob do
        post import_lorebooks_url,
             params: { file: [file], name: "Exact Name" },
             headers: { "Accept" => "text/html" }
      end
    end

    lorebook = Lorebook.order(created_at: :desc).first
    assert lorebook.pending?
    assert_equal user.id, lorebook.user_id
    assert_equal "private", lorebook.visibility
    assert_equal "Exact Name", lorebook.name
  end

  test "update clears file_sha256" do
    user = users(:member)
    lorebook = Lorebook.create!(
      name: "Editable Lorebook",
      status: "ready",
      visibility: "private",
      user: user,
      file_sha256: "abc123"
    )

    patch lorebook_url(lorebook), params: {
      lorebook: { name: "Renamed Lorebook" },
    }

    assert_redirected_to lorebooks_url
    lorebook.reload
    assert_equal "Renamed Lorebook", lorebook.name
    assert_nil lorebook.file_sha256
  end

  private

  def uploaded_fixture(path, content_type:)
    fixture_file_upload(file_fixture(path).to_s, content_type)
  end
end
