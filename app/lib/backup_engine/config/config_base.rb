require 'yaml_extend'
require 'powerpack/hash'

require_relative '../communicator.rb'
require_relative '../encryption/engine.rb'

module BackupEngine
  module Config
    class ParseError < StandardError
    end

    class ConfigBase
      def initialize(path:, logger:)
        @logger = logger

        config = YAML.ext_load_file(path).symbolize_keys

        _parse_communicator_block(config.fetch(:communicator).symbolize_keys)
        _parse_encryption_block(config.fetch(:encryption).symbolize_keys)

        yield(config) if block_given?
      rescue KeyError => e
        raise(ParseError, "Error parsing top level configuration: #{e}")
      end

      private

      def _parse_communicator_block(config)
        @communicator = BackupEngine::Communicator.new(config)
      end

      def _parse_encryption_block(config)
        # Currently only supporting asymmetric encryption with RSA keys
        raise('Only RSA encryption is supported') if config.fetch(:type) != 'RSA'

        @encryption_engine = BackupEngine::Encryption::Engines::ASymmetricRSA.new(communicator: @communicator,
                                                                                  keys: _process_encryption_keys(config.fetch(:keys), :data_keys),
                                                                                  logger: @logger)

        @manifest_encryption_engine = BackupEngine::Encryption::Engines::ASymmetricRSA.new(communicator: @communicator,
                                                                                           keys: _process_encryption_keys(config.fetch(:keys).merge(config.fetch(:manifest_only_keys)), :manifest_only_keys),
                                                                                           logger: @logger)
      rescue KeyError => e
        raise(ParseError, "Error parsing encryption block: #{e}")
      end

      def _process_encryption_keys(keys, key_class)
        encryption_keys = {}
        keys.each_pair do |name, key_config|
          # _parse_encryption_key is defined by the client class
          encryption_keys[name] = _parse_encryption_key(name, key_config.symbolize_keys, key_class)
        end
        encryption_keys
      end
    end
  end
end
