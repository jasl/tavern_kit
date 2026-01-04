# frozen_string_literal: true

# Playground space for solo roleplay (one human + AI characters).
#
# Enforces single human membership constraint.
# This is the primary space type for the Playground app.
#
class Spaces::Playground < Space
  validate :single_human_membership, on: :update

  private

  # Ensure only one human membership exists in a playground space.
  def single_human_membership
    human_count = space_memberships.active.where(kind: "human").count
    return if human_count <= 1

    errors.add(:base, "only one human membership is allowed in a playground space")
  end
end
