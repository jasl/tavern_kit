# frozen_string_literal: true

require "test_helper"

class CharactersControllerTest < ActionDispatch::IntegrationTest
  setup do
    clear_enqueued_jobs
    sign_in :member
  end

  test "update does not write nil talkativeness when blank (preserves default semantics)" do
    user = users(:member)

    character =
      Character.create!(
        name: "Owned No Talkativeness",
        user: user,
        status: "ready",
        visibility: "private",
        spec_version: 2,
        file_sha256: "owned_no_talk_#{SecureRandom.hex(8)}",
        data: {
          name: "Owned No Talkativeness",
          group_only_greetings: [],
        }
      )

    assert_not character.data.talkativeness?
    assert_in_delta 0.5, character.data.talkativeness_factor(default: 0.5), 0.0001

    patch character_url(character), params: {
      character: { data: { extensions: { talkativeness: "" } } },
    }

    assert_response :redirect
    character.reload
    assert_not character.data.talkativeness?
    assert_in_delta 0.5, character.data.talkativeness_factor(default: 0.5), 0.0001
  end

  test "create supports multiple files and enqueues one import job per file" do
    file1 = uploaded_fixture("characters/minimal_v2.json", content_type: "application/json")
    file2 = uploaded_fixture("characters/minimal_v3.json", content_type: "application/json")

    assert_difference ["Character.count", "CharacterUpload.count"], 2 do
      assert_enqueued_jobs 2, only: CharacterImportJob do
        post characters_url, params: { file: ["", file1, file2] }, headers: { "Accept" => "text/html" }
      end
    end

    assert_redirected_to characters_url
    assert_nil flash[:alert]
  end

  private

  def uploaded_fixture(path, content_type:)
    fixture_file_upload(file_fixture(path).to_s, content_type)
  end
end
