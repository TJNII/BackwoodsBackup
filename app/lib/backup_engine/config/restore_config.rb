require_relative 'config_base.rb'

module BackupEngine
  module Config
    class RestoreConfig < ConfigBase
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
