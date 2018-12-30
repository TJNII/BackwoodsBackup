require 'yaml'
require 'powerpack/hash'

require_relative '../communicator.rb'
require_relative '../encryption/engine.rb'

module BackupEngine
  module Config
    class ParseError < StandardError
    end

    class ConfigBase
      private

      def _parse_communicator_block(config)
        @communicator = BackupEngine::Communicator.new(config)
      end

      def _parse_encryption_block(config)
        # Currently only supporting asymmetric encryption with RSA keys
        raise('Only RSA encryption is supported') if config.fetch(:type) != 'RSA'

        encryption_keys = {}
        config.fetch(:keys).each_pair do |name, key_config|
          encryption_keys[name] = _parse_encryption_key(name, key_config.symbolize_keys)
        end

        @encryption_engine = BackupEngine::Encryption::Engines::ASymmetricRSA.new(communicator: @communicator,
                                                                                  keys: encryption_keys,
                                                                                  logger: @logger)
      rescue KeyError => e
        raise(ParseError, "Error parsing encryption block: #{e}")
      end
    end
  end
end
