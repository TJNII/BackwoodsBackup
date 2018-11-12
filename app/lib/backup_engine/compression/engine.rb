require_relative 'result.rb'

require 'zlib'

module BackupEngine
  module Compression
    class Engine
      def initialize(algorithm)
        @algorithm = algorithm.freeze
        if algorithm == "zlib"
          @compressor = Zlib::Deflate
          @decompressor = Zlib::Inflate
        else
          raise "Unsupported compression algorithm #{algorithm}"
        end
      end

      def compress(data)
        Result.new(@compressor.deflate(data), @algorithm)
      end

      def decompress(data)
        @decompressor.inflate(data)
      end
    end
  end
end
