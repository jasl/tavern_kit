# frozen_string_literal: true

require "test_helper"

module TavernKit
  class ChatHistoryTest < Minitest::Test
    def test_new_returns_in_memory_instance
      history = ChatHistory.new
      assert_instance_of ChatHistory::InMemory, history
    end

    def test_new_with_messages
      messages = [
        Prompt::Message.new(role: :user, content: "Hello"),
        Prompt::Message.new(role: :assistant, content: "Hi!"),
      ]
      history = ChatHistory.new(messages)

      assert_equal 2, history.size
      assert_equal :user, history.first.role
      assert_equal "Hello", history.first.content
    end

    def test_from_array
      messages = [
        Prompt::Message.new(role: :user, content: "Test"),
      ]
      history = ChatHistory.from_array(messages)

      assert_instance_of ChatHistory::InMemory, history
      assert_equal 1, history.size
    end

    def test_wrap_with_chat_history
      original = ChatHistory.new
      wrapped = ChatHistory.wrap(original)

      assert_same original, wrapped
    end

    def test_wrap_with_array
      messages = [{ role: :user, content: "Hello" }]
      wrapped = ChatHistory.wrap(messages)

      assert_instance_of ChatHistory::InMemory, wrapped
      assert_equal 1, wrapped.size
      assert_instance_of Prompt::Message, wrapped.first
      assert_equal :user, wrapped.first.role
    end

    def test_wrap_with_nil
      wrapped = ChatHistory.wrap(nil)

      assert_instance_of ChatHistory::InMemory, wrapped
      assert wrapped.empty?
    end

    def test_wrap_with_invalid_input_returns_history_with_coerced_messages
      # Duck typing: strings get wrapped into array and coerced to messages
      wrapped = ChatHistory.wrap("invalid")
      assert_kind_of ChatHistory::Base, wrapped
    end
  end

  module ChatHistory
    class InMemoryTest < Minitest::Test
      def setup
        @history = InMemory.new
      end

      def test_append_message_object
        message = Prompt::Message.new(role: :user, content: "Hello")
        @history.append(message)

        assert_equal 1, @history.size
        assert_equal :user, @history.first.role
        assert_equal "Hello", @history.first.content
      end

      def test_append_hash_with_symbol_keys
        assert_raises(ArgumentError) do
          @history.append(role: :user, content: "Hello")
        end
      end

      def test_append_hash_with_string_keys
        assert_raises(ArgumentError) do
          @history.append("role" => "user", "content" => "Hello")
        end
      end

      def test_append_returns_self_for_chaining
        result = @history.append(Prompt::Message.new(role: :user, content: "A"))

        assert_same @history, result
      end

      def test_shovel_operator
        @history << Prompt::Message.new(role: :user, content: "Hello")
        @history << Prompt::Message.new(role: :assistant, content: "Hi!")

        assert_equal 2, @history.size
      end

      def test_append_invalid_type
        assert_raises(ArgumentError) do
          @history.append("invalid")
        end
      end

      def test_each_yields_messages
        @history << Prompt::Message.new(role: :user, content: "Hello")
        @history << Prompt::Message.new(role: :assistant, content: "Hi!")

        roles = []
        @history.each { |m| roles << m.role }

        assert_equal %i[user assistant], roles
      end

      def test_each_returns_enumerator_without_block
        @history << Prompt::Message.new(role: :user, content: "Hello")

        enum = @history.each
        assert_instance_of Enumerator, enum
        assert_equal "Hello", enum.first.content
      end

      def test_enumerable_methods
        @history << Prompt::Message.new(role: :user, content: "Hello")
        @history << Prompt::Message.new(role: :assistant, content: "Hi!")
        @history << Prompt::Message.new(role: :user, content: "How are you?")

        # map
        roles = @history.map(&:role)
        assert_equal %i[user assistant user], roles

        # select
        user_messages = @history.select { |m| m.role == :user }
        assert_equal 2, user_messages.size

        # any?
        assert @history.any? { |m| m.role == :assistant }
      end

      def test_size_and_length
        assert_equal 0, @history.size
        assert_equal 0, @history.length

        @history << Prompt::Message.new(role: :user, content: "Hello")

        assert_equal 1, @history.size
        assert_equal 1, @history.length
      end

      def test_empty?
        assert @history.empty?

        @history << Prompt::Message.new(role: :user, content: "Hello")

        refute @history.empty?
      end

      def test_clear
        @history << Prompt::Message.new(role: :user, content: "Hello")
        @history << Prompt::Message.new(role: :assistant, content: "Hi!")

        result = @history.clear

        assert_same @history, result
        assert @history.empty?
      end

      def test_last
        @history << Prompt::Message.new(role: :user, content: "First")
        @history << Prompt::Message.new(role: :assistant, content: "Second")
        @history << Prompt::Message.new(role: :user, content: "Third")

        assert_equal "Third", @history.last.content
        assert_equal 2, @history.last(2).size
        assert_equal "Second", @history.last(2).first.content
      end

      def test_first
        @history << Prompt::Message.new(role: :user, content: "First")
        @history << Prompt::Message.new(role: :assistant, content: "Second")

        assert_equal "First", @history.first.content
        assert_equal 2, @history.first(2).size
      end

      def test_index_access
        @history << Prompt::Message.new(role: :user, content: "Hello")
        @history << Prompt::Message.new(role: :assistant, content: "Hi!")

        assert_equal "Hello", @history[0].content
        assert_equal "Hi!", @history[1].content
        assert_nil @history[99]
      end

      def test_to_a
        @history << Prompt::Message.new(role: :user, content: "Hello")

        arr = @history.to_a
        assert_instance_of Array, arr
        assert_equal 1, arr.size

        # Ensure it's a copy
        arr << Prompt::Message.new(role: :user, content: "More")
        assert_equal 1, @history.size
      end

      def test_user_message_count
        @history << Prompt::Message.new(role: :user, content: "Hello")
        @history << Prompt::Message.new(role: :assistant, content: "Hi!")
        @history << Prompt::Message.new(role: :user, content: "How are you?")
        @history << Prompt::Message.new(role: :system, content: "System message")

        assert_equal 2, @history.user_message_count
      end

      def test_assistant_message_count
        @history << Prompt::Message.new(role: :user, content: "Hello")
        @history << Prompt::Message.new(role: :assistant, content: "Hi!")
        @history << Prompt::Message.new(role: :assistant, content: "How can I help?")

        assert_equal 2, @history.assistant_message_count
      end

      def test_system_message_count
        @history << Prompt::Message.new(role: :system, content: "System 1")
        @history << Prompt::Message.new(role: :user, content: "Hello")
        @history << Prompt::Message.new(role: :system, content: "System 2")

        assert_equal 2, @history.system_message_count
      end

      def test_turn_count
        @history << Prompt::Message.new(role: :user, content: "Hello")
        @history << Prompt::Message.new(role: :assistant, content: "Hi!")
        @history << Prompt::Message.new(role: :user, content: "Question")

        assert_equal 2, @history.turn_count
      end

      def test_dup_creates_independent_copy
        @history << Prompt::Message.new(role: :user, content: "Hello")
        @history << Prompt::Message.new(role: :assistant, content: "Hi!")

        branch = @history.dup
        branch << Prompt::Message.new(role: :user, content: "Branch message")

        assert_equal 2, @history.size
        assert_equal 3, branch.size
        refute_same @history, branch
      end

      def test_initialize_with_messages
        messages = [
          Prompt::Message.new(role: :assistant, content: "Hi!"),
          Prompt::Message.new(role: :user, content: "Hello"),
        ]

        history = InMemory.new(messages)

        assert_equal 2, history.size
        assert_instance_of Prompt::Message, history.first
        assert_instance_of Prompt::Message, history.last
      end

      def test_count_with_block
        @history << Prompt::Message.new(role: :user, content: "Hello")
        @history << Prompt::Message.new(role: :assistant, content: "Hi!")
        @history << Prompt::Message.new(role: :user, content: "Question")

        assert_equal 2, @history.count { |m| m.role == :user }
        assert_equal 3, @history.count
      end

      # ========================================
      # Dump / Load Tests
      # ========================================

      def test_dump_returns_json_string
        @history << Prompt::Message.new(role: :user, content: "Hello")
        @history << Prompt::Message.new(role: :assistant, content: "Hi!")

        json = @history.dump
        assert_instance_of String, json

        parsed = JSON.parse(json)
        assert_equal 2, parsed.size
        assert_equal "user", parsed[0]["role"]
        assert_equal "Hello", parsed[0]["content"]
      end

      def test_dump_with_pretty_option
        @history << Prompt::Message.new(role: :user, content: "Hello")

        compact = @history.dump(pretty: false)
        pretty = @history.dump(pretty: true)

        refute_includes compact, "\n"
        assert_includes pretty, "\n"
      end

      def test_dump_includes_all_fields
        @history << Prompt::Message.new(
          role: :assistant,
          content: "Hi!",
          name: "Alice",
          swipes: ["Hi!", "Hello!", "Hey!"],
          swipe_id: 0,
          send_date: "2024-01-01T12:00:00Z"
        )

        json = @history.dump
        parsed = JSON.parse(json, symbolize_names: true)

        assert_equal "assistant", parsed[0][:role]
        assert_equal "Hi!", parsed[0][:content]
        assert_equal "Alice", parsed[0][:name]
        assert_equal ["Hi!", "Hello!", "Hey!"], parsed[0][:swipes]
        assert_equal 0, parsed[0][:swipe_id]
        assert_equal "2024-01-01T12:00:00Z", parsed[0][:send_date]
      end

      def test_to_a_hashes
        @history << Prompt::Message.new(role: :user, content: "Hello")
        @history << Prompt::Message.new(role: :assistant, content: "Hi!")

        hashes = @history.to_a_hashes
        assert_instance_of Array, hashes
        assert_equal 2, hashes.size
        assert_instance_of Hash, hashes[0]
        assert_equal "user", hashes[0][:role]
      end

      def test_load_from_json_string
        json = '[{"role":"user","content":"Hello"},{"role":"assistant","content":"Hi!"}]'
        history = InMemory.load(json)

        assert_instance_of InMemory, history
        assert_equal 2, history.size
        assert_equal :user, history[0].role
        assert_equal "Hello", history[0].content
        assert_equal :assistant, history[1].role
        assert_equal "Hi!", history[1].content
      end

      def test_load_restores_all_fields
        json = '[{"role":"assistant","content":"Hi!","name":"Alice","swipes":["Hi!","Hello!"],"swipe_id":1,"send_date":"2024-01-01"}]'
        history = InMemory.load(json)

        msg = history.first
        assert_equal :assistant, msg.role
        assert_equal "Hi!", msg.content
        assert_equal "Alice", msg.name
        assert_equal ["Hi!", "Hello!"], msg.swipes
        assert_equal 1, msg.swipe_id
        assert_equal "2024-01-01", msg.send_date
      end

      def test_from_hashes
        hashes = [
          { role: "user", content: "Hello" },
          { role: "assistant", content: "Hi!" },
        ]
        history = InMemory.from_hashes(hashes)

        assert_equal 2, history.size
        assert_equal :user, history[0].role
      end

      def test_dump_to_file_and_load_from_file
        @history << Prompt::Message.new(role: :user, content: "Hello")
        @history << Prompt::Message.new(role: :assistant, content: "Hi!")

        # Use a temp file
        require "tempfile"
        Tempfile.create(["chat_history", ".json"]) do |file|
          path = file.path

          # Dump to file
          result = @history.dump_to_file(path)
          assert_same @history, result

          # Verify file content
          content = File.read(path)
          assert_includes content, "Hello"

          # Load from file
          restored = InMemory.load_from_file(path)
          assert_equal 2, restored.size
          assert_equal :user, restored[0].role
          assert_equal "Hello", restored[0].content
        end
      end

      def test_roundtrip_preserves_data
        @history << Prompt::Message.new(role: :user, content: "Hello", name: "User1")
        @history << Prompt::Message.new(
          role: :assistant,
          content: "Hi!",
          swipes: ["Hi!", "Hello there!"],
          swipe_id: 0
        )

        json = @history.dump
        restored = InMemory.load(json)

        assert_equal @history.size, restored.size

        assert_equal @history[0].role, restored[0].role
        assert_equal @history[0].content, restored[0].content
        assert_equal @history[0].name, restored[0].name

        assert_equal @history[1].role, restored[1].role
        assert_equal @history[1].swipes, restored[1].swipes
        assert_equal @history[1].swipe_id, restored[1].swipe_id
      end
    end

    class BaseTest < Minitest::Test
      def test_base_methods_raise_not_implemented
        base = Base.new

        assert_raises(NotImplementedError) { base.append(Prompt::Message.new(role: :user, content: "Hello")) }
        assert_raises(NotImplementedError) { base.each }
        assert_raises(NotImplementedError) { base.size }
        assert_raises(NotImplementedError) { base.clear }
        assert_raises(NotImplementedError) { base.compress }
        assert_raises(NotImplementedError) { base.summarize }
      end
    end
  end
end
