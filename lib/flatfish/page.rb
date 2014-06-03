# -*- coding: utf-8 -*- #specify UTF-8 (unicode) characters
require_relative 'url'
require 'webrick'

module Flatfish 

  class Page < ActiveRecord::Base
    self.abstract_class = true
    @columns = []
    extend Flatfish::Url

    attr_reader :url, :data
    attr_accessor :cd

    # Setup - unpack the vars for the web page to be scraped
    #
    # csv - an array w/ all of the page specific
    # config - has some key deets, where to save images, etc that the page has to know
    # schema - dynamic column headers
    def setup(csv, config, schema, host, accepted_domain)
      #parse the csv
      @url, @path, @title  = csv[0], csv[1], csv[2]
      @fields = []
      csv[3..-1].each do |field|
        unless field.nil?
          @fields << (field.strip! || field)
        else
          @fields << -1 #flag
        end
      end

      #current directory, we want http://example.com/about/ or http://example.com/home/
      @cd = (@url[-1,1] == '/')? @url: @url.slice(0..@url.rindex('/'))
      @schema = schema
      @host = host
      @accepted_domain = accepted_domain
      @local_source = config['local_source'].nil? ? '': config['local_source']
      default_exts = ['.doc', '.docx', '.pdf', '.pptx', '.ppt', '.xls', '.xlsx']
      @file_whitelist = config['file_whitelist'].nil? ? default_exts : config['file_whitelist']
      @img_blacklist = config['img_blacklist'].nil? ? ['spacer.gif']: config['img_blacklist']

      # handle url == host, fix mangled @cd
      if @url == @host
        @cd = @url + '/'
      end
      Flatfish::Url.creds = {:http_basic_authentication => [config['basic_auth_user'], config['basic_auth_pass']]}
    end

    def process
      load_html
      self.attributes = prep
    end

    # load html from local or web
    def load_html
      file = @local_source + @url.sub(@host, '')
      if (@url != @host) && !@local_source.nil? && File.exists?(file)
        f = File.open(file)
        @doc = Nokogiri::XML(f)
        f.close
      else
        html = Flatfish::Url.open_url(@url)
        @doc = Nokogiri::HTML(html)
      end
    end

    def prep
      #default to csv, fallback to title element
      @title = @title.nil? ? @doc.title: @title

      #build a hash of field => data
      html = Hash.new
      @fields.each_with_index do |selectors, i|
        next if -1 == selectors
        html[@schema[i]] = ''

        selectors.split('&&').each do |selector|
          if selector[0] == '!'
            subtract = true
            selector = selector[1..-1]
          end
          update_hrefs(selector)
          update_imgs(selector)
          if @doc.css(selector).nil?
            field = ''
          else
            # sub tokens and gnarly MS Quotes
            field = @doc.css(selector).to_s.gsub("%5BFLATFISH", '[').gsub("FLATFISH%5D", ']').gsub(/[”“]/, '"').gsub(/[‘’]/, "'")
          end
          
          # remove any junk
          if subtract
            html[@schema[i][field] = ""
          else
            html[@schema[i]] +=  field
          end
        end

        # special case for menu fields
        if selectors.is_a? Numeric
          html[@schema[i]] = selectors
        end
      end
      @data = {
        'url' => @url,
        'title' => @title,
        'pathauto' => @path
      }
      @data.merge!(html)
    end

    # processes link tags
    # absolutifies and passes media links on for tokenization
    def update_hrefs(css_selector)
      @doc.css(css_selector + ' a').each do |a|

        href = Flatfish::Url.absolutify(a['href'], @cd)
        if href =~ /#{@accepted_domain}/  && @file_whitelist.include?(File.extname(href))
          media = get_media(href)
          href = "[FLATFISHmedia:#{media.id}FLATFISH]"
        end
          link = Flatfish::Link.find_or_create_by(url: href)
          a['href'] = "[FLATFISHlink:#{link.id}FLATFISH]"
      end
    end

    # processes image tags
    # absolutifies images and passes internal ones on for tokenization
    def update_imgs(css_selector)
      @doc.css(css_selector + ' img').each do |img|
        next if img['src'].nil?

        # absolutify and tokenize our images
        src = Flatfish::Url.absolutify(img['src'], @cd)
        if src =~ /#{@accepted_domain}/ && ! @img_blacklist.include?(File.basename(src))
          # check to see if it already exists
          media = get_media(src)
          #puts "GETTING MEDIA #{img['src']}"
          img['src'] = "[FLATFISHmedia:#{media.id}FLATFISH]"
        end
      end
    end

    def get_media(url)
      media = Flatfish::Media.find_by(url: url)
      if media.nil?
        media = Flatfish::Media.create(url: url) do |m|
          m.value = read_in_blob(url)
          m.destination_file = File.basename url
        end
        puts "Saved Media #{media.id}"
      end
      media
    end 

    # read in blob
    def read_in_blob(url)
      # assume local file
      file = url.sub(@host, @local_source)

      unless @local_source.nil? || !File.exists?(file)
        blob = file.read
      else
        # quick check to prevent double encoding
        if WEBrick::HTTPUtils.unescape(url) == url
          blob = Flatfish::Url.open_url(WEBrick::HTTPUtils.escape(url))
        else
          blob = Flatfish::Url.open_url(url)
        end
      end
      blob
    end

  end
end
