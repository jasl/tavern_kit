# frozen_string_literal: true

require "test_helper"

class PlaygroundsControllerTest < ActionDispatch::IntegrationTest
  setup do
    clear_enqueued_jobs
    sign_in :admin
  end

  test "show renders the playground page and records the last space visited in a cookie" do
    playground = spaces(:general)

    get playground_url(playground)
    assert_response :success
    assert_equal playground.id.to_s, cookies[:last_space]
    assert_select "h1", text: playground.name
  end

  test "show redirects to root for inaccessible playground" do
    other_user = users(:member)
    other_playground = Spaces::Playground.create!(name: "Secret Playground", owner: other_user)
    other_playground.space_memberships.create!(kind: "human", user: other_user, role: "owner", position: 0)

    get playground_url(other_playground)
    assert_redirected_to root_url
  end

  test "new displays form for creating a playground" do
    get new_playground_url
    assert_response :success
    assert_select "select[name='playground[prompt_settings][i18n][mode]']"
    assert_select "select[name='playground[prompt_settings][i18n][target_lang]']"
    assert_select "input[type='checkbox'][name='playground[prompt_settings][i18n][auto_vibe_target_lang]']"
  end

  test "create creates a playground and an owner membership" do
    ai = characters(:ready_v2)

    assert_difference "Spaces::Playground.count", 1 do
      assert_difference "SpaceMembership.count", 2 do
        post playgrounds_url, params: { playground: { name: "New Playground" }, character_ids: [ai.id] }
      end
    end

    playground = Spaces::Playground.order(:created_at, :id).last
    assert_equal users(:admin), playground.owner
    assert playground.playground?

    owner_membership = playground.space_memberships.find_by(user: users(:admin), kind: "human")
    assert owner_membership
    assert_equal "owner", owner_membership.role

    conversation = playground.conversations.root.first
    assert_redirected_to conversation_url(conversation)

    ai_membership = playground.space_memberships.find_by(character_id: ai.id, kind: "character")
    assert ai_membership
  end

  test "create requires at least one AI character" do
    assert_no_difference "Spaces::Playground.count" do
      post playgrounds_url, params: { playground: { name: "No Characters" } }
    end

    assert_response :unprocessable_entity
    assert_select ".alert.alert-error", text: /Please select at least one AI character/
  end

  test "create persists translation settings under prompt_settings.i18n" do
    ai = characters(:ready_v2)

    post playgrounds_url, params: {
      character_ids: [ai.id],
      playground: {
        name: "I18n Playground",
        prompt_settings: {
          i18n: {
            mode: "translate_both",
            target_lang: "ja",
            auto_vibe_target_lang: false,
            provider: { llm_provider_id: llm_providers(:mock_local).id },
            chunking: { max_chars: 2000 },
            cache: { enabled: true },
          },
        },
      },
    }

    assert_response :redirect

    playground = Spaces::Playground.order(:created_at, :id).last
    assert_equal "translate_both", playground.prompt_settings.i18n.mode
    assert_equal "ja", playground.prompt_settings.i18n.target_lang
    assert_equal false, playground.prompt_settings.i18n.auto_vibe_target_lang
    assert_equal llm_providers(:mock_local).id, playground.prompt_settings.i18n.provider.llm_provider_id
    assert_equal 2000, playground.prompt_settings.i18n.chunking.max_chars
    assert_equal true, playground.prompt_settings.i18n.cache.enabled

    conversation = playground.conversations.root.first
    assert_redirected_to conversation_url(conversation)
  end

  test "update treats prompt_settings.i18n.internal_lang as read-only" do
    playground = spaces(:general)
    assert_equal "en", playground.prompt_settings.i18n.internal_lang

    patch playground_url(playground), params: {
      playground: {
        prompt_settings: {
          i18n: {
            mode: "translate_both",
            internal_lang: "ja",
          },
        },
      },
    }

    assert_response :redirect

    playground.reload
    assert_equal "translate_both", playground.prompt_settings.i18n.mode
    assert_equal "en", playground.prompt_settings.i18n.internal_lang
  end

  test "update turning translation off cancels active translation runs" do
    Message.any_instance.stubs(:broadcast_update)

    playground = spaces(:general)
    message = messages(:ai_response)

    playground.update!(prompt_settings: playground.prompt_settings.to_h.deep_merge(i18n: { "mode" => "translate_both" }))
    Translation::Metadata.mark_pending!(message, target_lang: "zh-CN")

    run =
      TranslationRun.create!(
        conversation: message.conversation,
        message: message,
        kind: "message_translation",
        status: "queued",
        source_lang: "en",
        internal_lang: "en",
        target_lang: "zh-CN",
      )

    patch playground_url(playground), params: {
      playground: {
        prompt_settings: {
          i18n: {
            mode: "off",
          },
        },
      },
    }

    assert_response :redirect

    run.reload
    assert_equal "canceled", run.status
    assert_equal "disabled", run.error["code"]

    message.reload
    assert_nil message.metadata.dig("i18n", "translation_pending", "zh-CN")
  end

  test "create persists owner custom persona text to the owner membership" do
    ai = characters(:ready_v2)

    post playgrounds_url, params: {
      character_ids: [ai.id],
      playground: { name: "Persona Playground" },
      space_membership: { persona: "I am a friendly wizard who loves tea." },
    }

    assert_response :redirect

    playground = Spaces::Playground.order(:created_at, :id).last
    owner_membership = playground.space_memberships.find_by!(user: users(:admin), kind: "human")
    assert_equal "I am a friendly wizard who loves tea.", owner_membership.persona

    conversation = playground.conversations.root.first
    assert_redirected_to conversation_url(conversation)
  end

  test "create persists owner name override to the owner membership" do
    ai = characters(:ready_v2)

    post playgrounds_url, params: {
      character_ids: [ai.id],
      playground: { name: "Name Override Playground" },
      space_membership: { name_override: "The Wizard" },
    }

    assert_response :redirect

    playground = Spaces::Playground.order(:created_at, :id).last
    owner_membership = playground.space_memberships.find_by!(user: users(:admin), kind: "human")
    assert_equal "The Wizard", owner_membership.name_override
    assert_equal "The Wizard", owner_membership.display_name

    conversation = playground.conversations.root.first
    assert_redirected_to conversation_url(conversation)
  end

  test "create persists owner persona character to the owner membership" do
    ai = characters(:ready_v2)
    persona = characters(:ready_v3)

    post playgrounds_url, params: {
      character_ids: [ai.id],
      playground: { name: "Persona Character Playground" },
      space_membership: { character_id: persona.id },
    }

    assert_response :redirect

    playground = Spaces::Playground.order(:created_at, :id).last
    owner_membership = playground.space_memberships.find_by!(user: users(:admin), kind: "human")
    assert_equal persona.id, owner_membership.character_id
    assert_equal persona.name, owner_membership.display_name

    conversation = playground.conversations.root.first
    assert_redirected_to conversation_url(conversation)
  end

  test "create (full flow) sets owner persona character and creates AI memberships" do
    ai = characters(:ready_v2)
    persona = characters(:ready_v3)

    post playgrounds_url, params: {
      playground: { name: "Full Flow Persona Character Playground" },
      character_ids: [ai.id],
      space_membership: { character_id: persona.id },
    }

    assert_response :redirect

    playground = Spaces::Playground.order(:created_at, :id).last
    owner_membership = playground.space_memberships.find_by!(user: users(:admin), kind: "human")
    assert_equal "owner", owner_membership.role
    assert_equal persona.id, owner_membership.character_id
    assert_equal persona.name, owner_membership.display_name

    ai_membership = playground.space_memberships.find_by(character_id: ai.id, kind: "character")
    assert ai_membership

    conversation = playground.conversations.root.first
    assert_redirected_to conversation_url(conversation)
  end

  test "create (full flow) persists owner name override to the owner membership" do
    ai = characters(:ready_v2)

    post playgrounds_url, params: {
      playground: { name: "Full Flow Name Override Playground" },
      character_ids: [ai.id],
      space_membership: { name_override: "The Wizard" },
    }

    assert_response :redirect

    playground = Spaces::Playground.order(:created_at, :id).last
    owner_membership = playground.space_memberships.find_by!(user: users(:admin), kind: "human")
    assert_equal "The Wizard", owner_membership.name_override
    assert_equal "The Wizard", owner_membership.display_name

    conversation = playground.conversations.root.first
    assert_redirected_to conversation_url(conversation)
  end

  test "create rejects using the same character as both AI participant and persona character" do
    ai_and_persona = characters(:ready_v2)

    assert_no_difference "Spaces::Playground.count" do
      assert_no_difference "SpaceMembership.count" do
        post playgrounds_url, params: {
          playground: { name: "Conflict Persona Playground" },
          character_ids: [ai_and_persona.id],
          space_membership: { character_id: ai_and_persona.id },
        }
      end
    end

    assert_response :unprocessable_entity
    assert_select ".alert.alert-error", text: /Persona character cannot also be selected as an AI participant/
  end

  test "create persists TavernKit preset settings under prompt_settings.preset" do
    ai = characters(:ready_v2)

    post playgrounds_url, params: {
      character_ids: [ai.id],
      playground: {
        name: "Preset Playground",
        prompt_settings: {
          preset: {
            main_prompt: "CUSTOM MAIN PROMPT",
            post_history_instructions: "CUSTOM PHI",
            authors_note: "CUSTOM AN",
            authors_note_frequency: 2,
            authors_note_position: "before_prompt",
            authors_note_depth: 7,
            message_token_overhead: 12,
          },
        },
      },
    }

    assert_response :redirect

    playground = Spaces::Playground.order(:created_at, :id).last
    assert_equal "CUSTOM MAIN PROMPT", playground.prompt_settings.preset.main_prompt
    assert_equal "CUSTOM PHI", playground.prompt_settings.preset.post_history_instructions
    assert_equal "CUSTOM AN", playground.prompt_settings.preset.authors_note
    assert_equal 2, playground.prompt_settings.preset.authors_note_frequency
    assert_equal "before_prompt", playground.prompt_settings.preset.authors_note_position
    assert_equal 7, playground.prompt_settings.preset.authors_note_depth
    assert_equal 12, playground.prompt_settings.preset.message_token_overhead

    conversation = playground.conversations.root.first
    assert_redirected_to conversation_url(conversation)
  end

  test "update broadcasts queue_updated so open conversation tabs get the latest during_generation policy" do
    playground =
      Spaces::Playground.create!(
        name: "Policy Live Update Test",
        owner: users(:admin),
        reply_order: "list",
        during_generation_user_input_policy: "reject"
      )

    playground.space_memberships.grant_to(users(:admin), role: "owner")
    playground.space_memberships.grant_to(characters(:ready_v2))

    conversation = playground.conversations.create!(title: "Main", kind: "root")

    TurnScheduler::Broadcasts.expects(:queue_updated).with(conversation).once

    patch playground_url(playground),
          params: { playground: { during_generation_user_input_policy: "restart" } },
          as: :turbo_stream

    assert_response :success
    assert_equal "restart", playground.reload.during_generation_user_input_policy
  end
end
