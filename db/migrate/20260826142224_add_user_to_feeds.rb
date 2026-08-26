class AddUserToFeeds < ActiveRecord::Migration[8.1]
  def change
    # Nullable for now: existing feeds predate user accounts and have no owner yet.
    # Backfilled and tightened to null: false in a follow-up migration once the
    # first account exists (see FinalizeFeedsUserIdNotNull).
    add_reference :feeds, :user, null: true, foreign_key: true
  end
end
