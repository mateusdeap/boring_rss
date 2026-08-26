class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :feeds, dependent: :destroy
  has_many :items, through: :feeds

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
