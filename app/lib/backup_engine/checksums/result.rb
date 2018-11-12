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
        if other.is_a? BackupEngine::Checksums::Result
          return false if other.algorithm != @algorithm
          return false if other.checksum != @checksum
          return true
        elsif other.is_a? Hash
          return false if other.fetch('algorithm')  != @algorithm
          return false if other.fetch('checksum') != @checksum
          return true
        else
          raise("Can't compare BackupEngine::Checksums::Result to #{other.class}")
        end
      end
    end
  end
end
