require_relative 'result.rb'
require_relative 'engines/zlib'

module BackupEngine
  module Compression
    class DecompressionLengthMismatch < StandardError
    end

    class Engine
      def self.init_engine(algorithm:)
        raise "Nil compression algorithm" if algorithm.nil?
        return BackupEngine::Compression::Engines::Zlib.new if algorithm == "zlib"
        raise "Unsupported compression algorithm #{algorithm}"
      end

      def self.decompress(metadata:, payload:)
        raise(DecompressionLengthMismatch, "Input Length Mismatch: #{metadata[:compressed_length]}:#{payload.length}") if payload.length != metadata[:compressed_length]
        engine = init_engine(algorithm: metadata[:algorithm])
        output = engine.decompress(payload).force_encoding(metadata[:encoding])
        raise(DecompressionLengthMismatch, "Output Length Mismatch: #{metadata[:uncompressed_length]}:#{output.length}") if output.length != metadata[:uncompressed_length]
        return output
      end
    end
  end
end
