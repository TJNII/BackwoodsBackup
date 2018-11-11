require_relative 'result.rb'

module BackupEngine
  module Encryption
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
