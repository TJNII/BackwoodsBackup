require_relative 'config_base.rb'

module BackupEngine
  module Config
    class RestoreConfig < ConfigBase
      attr_reader :logger, :communicator, :encryption_engine, :paths, :host, :checksum_engine, :compression_engine, :path_exclusions, :chunk_size

      def initialize(path:, logger:)
        @logger = logger

        config = YAML.load_file(path).symbolize_keys

        # Mandatory blocks
        _parse_communicator_block(config.fetch(:communicator).symbolize_keys)
        _parse_encryption_block(config.fetch(:encryption).symbolize_keys)
      rescue KeyError => e
        raise(ParseError, "Error parsing top level configuration: #{e}")
      end

      def to_engine_hash
        return {
          encryption_engine: @encryption_engine,
          logger: @logger
        }
      end

      private

      def _parse_encryption_key(name, config, _key_class)
        return { private: File.read(config.fetch(:private_key)) }
      rescue KeyError => e
        raise(ParseError, "Error parsing encryption key #{name} config: #{e}")
      rescue Errno::ENOENT => e
        raise(ParseError, "Error parsing encryption key #{name} config: #{e}")
      end
    end
  end
end
