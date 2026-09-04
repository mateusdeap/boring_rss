class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :feeds, dependent: :destroy
  has_many :items, through: :feeds

  enum :theme, { system: "system", light: "light", dark: "dark" }, default: "system"

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
