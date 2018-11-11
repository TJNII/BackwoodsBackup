require 'digest'
require 'json'
require_relative 'result.rb'

module BackupEngine
  module Checksums
    class Engine
      def initialize(algorithm)
        @algorithm = algorithm.freeze
        if algorithm == "sha256"
          @engine = Digest::SHA256
        else
          raise "Unsupported checksum algorithm #{algorithm}"
        end
      end

      def file(path)
        Result.new(@engine.file(path).hexdigest, @algorithm)
      end      

      def block(data)
        Result.new(@engine.hexdigest(data), @algorithm)
      end
    end
  end
end
