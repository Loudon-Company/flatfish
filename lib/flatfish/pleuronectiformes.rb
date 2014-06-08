require_relative 'page'

module Flatfish

  class Pleuronectiformes
    attr_reader :config, :schema, :klasses

    # load in the config
    def initialize(ymal)
      @config = YAML.load_file(ymal)
      db_conn() # establish AR conn
      @klasses = Hash.new
    end

    # main loop for flatfish
    def ingurgitate
      create_helper_tables
      @tables = {'Link' => 'links', 'Media' => 'media'}

      @config["types"].each do |k,v|
        next if v["csv"].nil?
        @csv_file = v["csv"]
        @host = v["host"]
        @tables[k] = v["table"].nil? ? k.tableize : v["table"]
        @accepted_domain = v["accepted_domain"].nil? ? @host : v["accepted_domain"]
        create_klass(k)
        parse(k)
      end
      update_links_table
      output_schema
    end

    # Create the Klass
    # create table if necessary: table must exist!
    # create dynamic model
    def create_klass(k)
        # commence hackery
        create_table(k, @tables[k]) unless ActiveRecord::Base.connection.tables.include?(@tables[k])
        @klass = Class.new(Page)
        @klasses[k] = @klass
        @klass.table_name = @tables[k]
    end

    def create_table(klass, table)
      load_csv
      Flatfish::CreateKlass.setup(@schema, table)
    end

    def create_helper_tables
      Flatfish::CreateMedia.setup unless Flatfish::Media.table_exists?
      Flatfish::CreateLink.setup unless Flatfish::Link.table_exists?
    end

    #load csv, set schema
    def load_csv
      csv = CSV.read(@csv_file)
      @schema = csv.shift[3..-1]
      return csv
    end

    # loop thru csv
    def parse(k)
      csv = load_csv
      @cnt = 0
      csv.each do |row|
        begin
          break if @cnt == @config['max_rows']
          @cnt += 1
          page = @klass.find_or_create_by(url: row[0])
          puts "Processing #{k}.#{page.id} with URL #{row[0]}"
          page.setup(row, @config, @schema, @host, @accepted_domain)
          page.process
          page.save!
        rescue Exception => e
          if e.message =~ /(redirection forbidden|404 Not Found)/
            puts "URL: #{page.url} #{e}"
          else
            puts "URL: #{page.url} ERROR: #{e} MESSAGE: #{e.backtrace}"
          end
        end
      end
    end

    def update_links_table
      Link.all.each do |link|
        link_updated = false
        @klasses.each_pair do |k,v|
          if (origin = v.find_by(url: link[:url]))
            link.update_attributes(:map_type => k, :map_id => origin.id)
            link_updated = true
            next
          end
        end

        # set a flag since we were unable to find the migrated content
        # this would happen if a legacy page was not migrated
        if ! link_updated
          link.update_attributes(:map_id => -1)
        end
      end
    end

    # generate a dynamic schema.yml for Migrate mapping
    def output_schema
      # TODO REFACTOR THIS ISH
      klasses = @klasses
      File.open('schema.yml', 'w') do |out|
        output = Hash.new
        output["schema"] = Hash.new
        klasses.merge!({"Media" => Flatfish::Media, "Link" => Flatfish::Link})

        klasses.each_pair do |k,v|
          klass_attributes = Hash.new
          v.new.attributes.each { |a| klass_attributes[a[0]] = split_type(v.columns_hash[a[0]].sql_type) }
          output["schema"].merge!({k => {"machine_name" => @tables[k], "fields" => klass_attributes, "primary key" => ["id"]}})
        end
        out.write output.to_yaml
      end
    end

    # helper function to convert AR sql_type to
    # Drupal format;
    # eg :type => varchar(255) to :type => varchar, :length => 255
    def split_type type
      if type =~ /\(/ then
        x = type.split("(")
        return {"type" => x[0], "length" => x[1].sub(")","").to_i }
      else
        return {"type" => type}
      end
    end


    def db_conn
      ActiveRecord::Base.establish_connection(
                                        :adapter=> "mysql2",
                                        :host => "localhost",
                                        :username => @config['db_user'],
                                        :password => @config['db_pass'],
                                        :database=> @config['db']
                                       )
    end

  end

end
