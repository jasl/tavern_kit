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
end
