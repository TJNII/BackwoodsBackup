require_relative 'result.rb'

require 'zlib'

module BackupEngine
  module Compression
    class Engine
      def initialize(algorithm)
        @algorithm = algorithm.freeze
        if algorithm == "zlib"
          @engine = Zlib::Deflate
        else
          raise "Unsupported compression algorithm #{algorithm}"
        end
      end

      def compress(data)
        Result.new(@engine.deflate(data), @algorithm)
      end
    end
  end
end
