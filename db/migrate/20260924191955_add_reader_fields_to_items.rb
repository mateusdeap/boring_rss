class AddReaderFieldsToItems < ActiveRecord::Migration[8.1]
  class MigrationItem < ActiveRecord::Base
    self.table_name = "items"
  end

  def change
    add_column :items, :author, :string
    # full / excerpt / empty (Item::CONTENT_KINDS), and the feed element the
    # body came from — both decided at ingest from markup alone.
    add_column :items, :content_kind, :string, null: false, default: "empty"
    add_column :items, :content_source, :string
    add_column :items, :word_count, :integer, null: false, default: 0
    add_column :items, :image_count, :integer, null: false, default: 0
    add_column :items, :link_count, :integer, null: false, default: 0

    # Existing items only ever stored one body (RSS <description>, or Atom
    # <summary> falling back to <content>), and which element it was wasn't
    # kept — so a stored body counts as an excerpt of unknown source.
    reversible do |dir|
      dir.up do
        MigrationItem.reset_column_information
        MigrationItem.where.not(summary: [ nil, "" ]).find_each do |item|
          fragment = Nokogiri::HTML5.fragment(item.summary)
          item.update_columns(
            content_kind: "excerpt",
            word_count: fragment.text.split.size,
            image_count: fragment.css("img").size,
            link_count: fragment.css("a[href]").size
          )
        end
      end
    end
  end
end
