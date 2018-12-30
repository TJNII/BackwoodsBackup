require_relative 'config_base.rb'
require_relative '../checksums/engine.rb'
require_relative '../compression/engine.rb'

module BackupEngine
  module Config
    class BackupConfig < ConfigBase
      attr_reader :logger, :communicator, :encryption_engine, :paths, :host, :checksum_engine, :compression_engine, :path_exclusions, :chunk_size

      def initialize(path:, logger:)
        @logger = logger

        config = YAML.load_file(path).symbolize_keys

        # Mandatory blocks
        _parse_communicator_block(config.fetch(:communicator).symbolize_keys)
        _parse_encryption_block(config.fetch(:encryption).symbolize_keys)
        @paths = config.fetch(:paths)
        @host = config.fetch(:host)

        # Optional blocks
        @checksum_engine = BackupEngine::Checksums::Engine.init_engine(algorithm: config.fetch(:checksum_algorithm, 'sha256'))
        @compression_engine = BackupEngine::Compression::Engine.init_engine(algorithm: config.fetch(:compression_algorithm, 'zlib'))
        @path_exclusions = config.fetch(:path_exclusions, [])

        @chunk_size = config.fetch(:chunk_size, 1048576)
        @logger.warn('Chunk sizes under 128KB or over 30MB may result in increased S3 costs and/or degraded performance') if @chunk_size < (128 * 1024) || @chunk_size > (30 * 1024 * 1024)
      rescue KeyError => e
        raise(ParseError, "Error parsing top level configuration: #{e}")
      end

      def to_engine_hash
        return {
          checksum_engine: @checksum_engine,
          encryption_engine: @encryption_engine,
          compression_engine: @compression_engine,
          host: @host,
          chunk_size: @chunk_size,
          logger: @logger,
          path_exclusions: @path_exclusions
        }
      end

      private

      def _parse_encryption_key(name, config)
        if config.key?(:private_key)
          @logger.warn('The backup client does not require private encryption keys')
          @logger.warn('Storing the private key on the backup host is not secure.')
        end

        return { public: File.read(config.fetch(:public_key)) }
      rescue KeyError => e
        raise(ParseError, "Error parsing encryption key #{name} config: #{e}")
      rescue Errno::ENOENT => e
        raise(ParseError, "Error parsing encryption key #{name} config: #{e}")
      end
    end
  end
end
