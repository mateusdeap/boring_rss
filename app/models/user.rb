class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :feeds, dependent: :destroy
  has_many :folders, dependent: :destroy
  has_many :items, through: :feeds

  # The left pane's mode (RDR-01 FeedTree): Groups, the default, lists
  # folders as reading rivers; Feeds lists every feed for managing them.
  enum :tree_mode, { groups: "groups", feeds: "feeds" }, default: "groups", prefix: true, validate: true

  enum :theme, { system: "system", light: "light", dark: "dark" }, default: "system"

  # Reader text settings (the reader's TEXT bar): one app-wide choice per
  # user, stored here so it follows them across devices.
  READER_TEXT_SIZES = (14..22)
  READER_MEASURES = [ 60, 68, 76 ].freeze

  validates :reader_text_size, inclusion: { in: READER_TEXT_SIZES }
  validates :reader_measure, inclusion: { in: READER_MEASURES }

  normalizes :email_address, with: ->(e) { e.strip.downcase }
end
