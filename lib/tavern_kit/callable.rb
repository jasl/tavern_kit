# frozen_string_literal: true

# TavernKit uses a uniform "callable" convention: many internal registries store
# blocks/lambdas and invoke them via `#execute(...)` (similar to middleware).
#
# Ruby Procs use `#call`, so we provide a small compatibility shim for internal
# usage. This is intentionally minimal and only adds the method when missing.
class Proc
  alias execute call unless method_defined?(:execute)
end
