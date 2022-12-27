require_relative 'config_base.rb'

module BackupEngine
  module Config
    class CleanConfig < ConfigBase
      attr_reader :min_block_age, :min_manifest_age, :min_set_manifests, :verify_block_checksum

      def initialize(kwargs)
        super(**kwargs) do |config|
          _parse_cleaner_block(config.fetch(:cleaner).symbolize_keys)
        end
      end

      def to_engine_hash
        return {
          encryption_engine: @manifest_encryption_engine,
          logger: @logger,
          min_block_age: @min_block_age,
          min_manifest_age: @min_manifest_age,
          min_set_manifests: @min_set_manifests,
          verify_block_checksum: @verify_block_checksum
        }
      end

      private

      def _parse_cleaner_block(config)
        @min_block_age = config.fetch(:min_block_age)
        @min_manifest_age = config.fetch(:min_manifest_age)
        @min_set_manifests = config.fetch(:min_set_manifests)
        @verify_block_checksum = config.fetch(:verify_block_checksum, false)
      rescue KeyError => e
        raise(ParseError, "Error parsing cleaner configuration: #{e}")
      end

      def _parse_encryption_key(name, config, key_class)
        if key_class != :manifest_only_keys
          @logger.warn('The cleaner only requires manifest private keys')
          @logger.warn('Storing the data keys on the cleaner host is not secure.')
          @logger.warn('Cleaner config should be unique from backup/restore config as it is global.')
          return {}
        end

        return { private: File.read(config.fetch(:private_key)) }
      rescue KeyError => e
        raise(ParseError, "Error parsing encryption key #{name} config: #{e}")
      rescue Errno::ENOENT => e
        raise(ParseError, "Error parsing encryption key #{name} config: #{e}")
      end
    end
  end
end
