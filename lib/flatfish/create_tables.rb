module Flatfish 

  class CreateKlass < ActiveRecord::Migration
    # assume every klass has a URL, Path(auto), Title
    # pass in additional columns from CSV
    def self.setup(schema, klass)
      k = klass.tableize.to_sym
      create_table(k) do |t|
        t.string :url
        t.string :pathauto
        t.string :title
      end
      schema.each do |column|
        add_column(k, column.gsub(/\s+/, '_').downcase.to_sym, :text, limit: 16777215)
      end
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
    end
  end

  # a table to store all links regardless of content type
  class CreateLinks < ActiveRecord::Migration
    #create flatfish_links table
    def self.setup
      create_table :links do |t|
        t.string :url
      end
    end
  end

end
