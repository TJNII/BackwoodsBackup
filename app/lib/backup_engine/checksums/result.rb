require 'json'

module BackupEngine
  module Checksums
    class Result
      attr_reader :checksum, :algorithm
      
      def initialize(checksum, algorithm)
        @checksum = checksum.freeze
        @algorithm = algorithm.freeze
      end

      def to_s
        "#{@algorithm}:#{@checksum}"
      end

      def to_hash
        {
          algorithm: @algorithm,
          checksum: @checksum
        }
      end

      def to_json(options = {})
        JSON.pretty_generate(to_hash, options)
      end

      def ==(other)
        return false if other.algorithm != @algorithm
        return false if other.checksum != @checksum
        return true
      end
    end
  end
end
