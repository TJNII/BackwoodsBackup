require 'powerpack/hash'
require 'digest'
require 'json'

require_relative 'result.rb'
require_relative 'engines/sha256.rb'

module BackupEngine
  module Checksums
    module Engine
      def self.init_engine(algorithm:)
        return BackupEngine::Checksums::Engines::SHA256.new if algorithm == "sha256"
        raise "Unsupported checksum algorithm #{algorithm}"
      end
      
      def self.parse(input)
        if input.is_a? BackupEngine::Checksums::Result
          return result
        elsif input.is_a? String
          split_str = input.split(':')
          raise("Failed to parse #{input} as string") if split_str.length != 2
          return BackupEngine::Checksums::Result.new(algorithm: split_str[0], checksum: split_str[1])
        elsif input.is_a? Hash
          return BackupEngine::Checksums::Result.new(input.symbolize_keys)
        else
          raise("Cannot parse input type #{input.class}")
        end
      end
    end
  end
end
