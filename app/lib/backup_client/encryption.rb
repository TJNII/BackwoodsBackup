require 'digest'

module BackupClient
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

    class Engine
      def initialize(algorithm)
        @algorithm = algorithm.freeze
        if algorithm == "none"
          @engine = :none
        else
          raise "Unsupported encryption algorithm #{algorithm}"
        end
      end

      def encrypt(data)
        # TODO: Actually do the thing
        Result.new(data, @engine)
      end
    end
  end
end
