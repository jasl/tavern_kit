class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :name, null: false
      t.string :email, index: { unique: true, where: "email IS NOT NULL" }
      t.string :password_digest
      t.string :role, default: "member", null: false      # member, moderator, administrator
      t.string :status, default: "active", null: false    # active, inactive

      t.timestamps
    end
  end
end
