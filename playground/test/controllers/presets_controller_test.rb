# frozen_string_literal: true

require "test_helper"

class PresetsControllerTest < ActionDispatch::IntegrationTest
  setup do
    clear_enqueued_jobs
    sign_in :member

    # Victim membership in a different space (member user is not a member of :general).
    @victim_membership = space_memberships(:admin_in_general)

    # Give the victim distinctive settings so the test would catch exfiltration if authorization fails.
    @victim_membership.update!(
      llm_provider: llm_providers(:openai),
      settings: {
        "llm" => {
          "providers" => {
            "openai" => {
              "generation" => {
                "temperature" => 0.99,
              },
            },
          },
        },
        "preset" => {
          "main_prompt" => "SECRET PROMPT",
        },
      }
    )
  end

  test "create returns not_found for memberships outside current user's spaces" do
    assert_no_difference "Preset.count" do
      post presets_url, params: {
        preset: {
          name: "Stolen Preset",
          membership_id: @victim_membership.id,
        },
      }
    end

    assert_response :not_found
  end

  test "update returns not_found for memberships outside current user's spaces" do
    attacker_preset = Preset.create!(
      name: "Attacker Preset",
      user: users(:member),
      generation_settings: { "temperature" => 0.1 },
      preset_settings: { "main_prompt" => "attacker" }
    )

    patch preset_url(attacker_preset), params: { membership_id: @victim_membership.id }

    assert_response :not_found

    attacker_preset.reload
    assert_equal 0.1, attacker_preset.generation_settings_as_hash["temperature"]
    assert_equal "attacker", attacker_preset.preset_settings_as_hash["main_prompt"]
  end

  test "apply returns not_found for memberships outside current user's spaces" do
    original_preset = Preset.create!(name: "Original Preset")
    other_preset = Preset.create!(name: "Other Preset")

    @victim_membership.update!(preset: original_preset)

    post apply_presets_url, params: { membership_id: @victim_membership.id, preset_id: other_preset.id }

    assert_response :not_found

    @victim_membership.reload
    assert_equal original_preset.id, @victim_membership.preset_id
  end

  test "update returns not_found for presets not owned by the current user" do
    my_membership = space_memberships(:member_in_ai_chat)

    victim_preset = Preset.create!(
      name: "Victim Preset",
      user: users(:admin),
      generation_settings: { "temperature" => 0.25 },
      preset_settings: { "main_prompt" => "victim" }
    )

    patch preset_url(victim_preset), params: { membership_id: my_membership.id }

    assert_response :not_found

    victim_preset.reload
    assert_equal 0.25, victim_preset.generation_settings_as_hash["temperature"]
    assert_equal "victim", victim_preset.preset_settings_as_hash["main_prompt"]
  end

  test "destroy returns not_found for presets not owned by the current user" do
    victim_preset = Preset.create!(name: "Victim Preset", user: users(:admin))

    assert_no_difference "Preset.count" do
      delete preset_url(victim_preset)
    end

    assert_response :not_found
  end

  test "apply returns not_found for presets not visible to the current user" do
    my_membership = space_memberships(:member_in_ai_chat)
    original_preset = Preset.create!(name: "Original Preset")

    victim_preset = Preset.create!(
      name: "Victim Preset",
      user: users(:admin),
      preset_settings: { "main_prompt" => "victim" }
    )

    my_membership.update!(preset: original_preset)

    post apply_presets_url, params: { membership_id: my_membership.id, preset_id: victim_preset.id }

    assert_response :not_found

    my_membership.reload
    assert_equal original_preset.id, my_membership.preset_id
  end

  test "apply turbo_stream returns not_found with turbo stream response when preset is missing" do
    my_membership = space_memberships(:member_in_ai_chat)

    post apply_presets_url,
         params: { membership_id: my_membership.id, preset_id: 999_999_999 },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :not_found
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "<turbo-stream"
  end

  test "import supports multiple files" do
    file1 = uploaded_fixture("presets/tavernkit_one.json", content_type: "application/json")
    file2 = uploaded_fixture("presets/tavernkit_two.json", content_type: "application/json")

    assert_difference "Preset.count", 2 do
      post import_presets_url, params: { file: ["", file1, file2] }, headers: { "Accept" => "text/html" }
    end

    assert_redirected_to presets_url
    assert_nil flash[:alert]
  end

  test "import continues when some files fail" do
    ok = uploaded_fixture("presets/tavernkit_one.json", content_type: "application/json")
    bad = uploaded_fixture("presets/invalid.json", content_type: "application/json")

    assert_difference "Preset.count", 1 do
      post import_presets_url, params: { file: [ok, bad] }, headers: { "Accept" => "text/html" }
    end

    assert_redirected_to presets_url
    assert flash[:alert].present?
  end

  private

  def uploaded_fixture(path, content_type:)
    fixture_file_upload(file_fixture(path).to_s, content_type)
  end
end
