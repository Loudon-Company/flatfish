module Flatfish 

  class CreateKlass < ActiveRecord::Migration
    # assume every klass has a URL, Path(auto), Title
    # pass in additional columns from CSV
    def self.setup(schema, table)
      k = table.to_sym
      create_table(k) do |t|
        t.string :url
        t.string :pathauto
        t.string :title
      end
      schema.each do |column|
        if column =~ /menu_parent|menu/
          add_column(k, column.to_sym, :integer)
        else
          add_column(k, column.gsub(/\s+/, '_').downcase.to_sym, :text, limit: 16777215)
        end
      end
      add_index table, ["url"], name: "index_#{table}_on_url", using: :btree
    end
  end

  # a table to store file/image blobs
  class CreateMedia < ActiveRecord::Migration
    #create media table
    def self.setup
      create_table :media do |t|
        t.string :url
        t.string :destination_file
        # options for mysql are 16mb or 4gb
        t.binary :value, :limit => 4294967295
      end
      add_index "media", ["url"], name: "index_media_on_url", using: :btree
    end
  end

  # a table to store all links regardless of content type
  class CreateLink < ActiveRecord::Migration
    #create flatfish_links table
    def self.setup
      create_table :links do |t|
        t.string :url
        t.string :map_type
        t.integer :map_id
      end
      add_index "links", ["url"], name: "index_links_on_url", using: :btree
      add_index "links", ["map_id"], name: "index_links_on_map_id", using: :btree
    end
  end

end
