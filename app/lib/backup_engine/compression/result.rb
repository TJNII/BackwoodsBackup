module BackupEngine
  module Compression
    class Result
      attr_reader :payload, :algorithm, :compressed_length, :uncompressed_length
      
      def initialize(payload:, algorithm:, encoding:, uncompressed_length:)
        @payload = payload.freeze
        @algorithm = algorithm.freeze
        @compressed_length = payload.length.freeze
        @uncompressed_length = uncompressed_length.freeze
        @encoding = encoding.freeze
      end

      def metadata
        { algorithm: @algorithm,
          encoding: @encoding,
          compressed_length: @compressed_length,
          uncompressed_length: @uncompressed_length
        }.freeze
      end

      def compression_percent
        100 - (@compressed_length.to_f / @uncompressed_length * 100)
      end

      def ==(other)
        return false if other.length != @length
        return false if other.algorithm != @algorithm
        return false if other.payload != @payload
        return true
      end
    end
  end
end
