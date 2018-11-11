module BackupEngine
  module Encryption
    class Result
      attr_reader :payload, :algorithm, :length
      
      def initialize(payload, algorithm)
        @payload = payload.freeze
        @algorithm = algorithm.freeze
        @length = payload.length
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
