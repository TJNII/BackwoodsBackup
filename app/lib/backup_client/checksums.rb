require 'digest'

module BackupClient
  class Checksums
    class Result
      attr_reader :checksum, :algorithm
      
      def initialize(checksum, algorithm)
        @checksum = checksum.freeze
        @algorithm = algorithm.freeze
      end

      def to_s
        "#{@algorithm}:#{@checksum}"
      end

      def to_json
        {
          algorithm: @algorithm,
          checksum: @checksum
        }
      end

      def ==(other)
        return false if other.algorithm != @algorithm
        return false if other.checksum != @checksum
        return true
      end
    end

    class Engine
      def initialize(algorithm)
        @algorithm = algorithm.freeze
        if algorithm == "sha256"
          @engine = Digest::SHA256.new
        else
          raise "Unsupported checksum algorithm #{algorithm}"
        end
      end

      def file(path)
        Result.new(@engine.file(path).hexdigest, @algorithm)
      end      

      def block(data)
        Result.new(@engine.digest(data).hexdigest, @algorithm)
      end
    end
  end
end
