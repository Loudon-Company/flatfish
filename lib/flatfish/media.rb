module Flatfish 
  class Media < ActiveRecord::Base
    attr_reader :url, :value, :destination_file
  end
end
