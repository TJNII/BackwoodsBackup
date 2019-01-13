require 'powerpack/hash'

require_relative 'communicator_backend/filesystem.rb'
require_relative 'communicator_backend/s3.rb'
require_relative 'communicator_backend/encoder.rb'

module BackupEngine
  class Communicator
    def initialize(type:, backend_config:)
      @backend = case type
                 when 'filesystem'
                   CommunicatorBackend::Filesystem.new(backend_config.symbolize_keys)
                 when 's3'
                   CommunicatorBackend::S3.new(backend_config.symbolize_keys)
                 else
                   raise("Unknown communicator type #{type}")
                 end
    end

    def date(path:)
      @backend.date(path: path)
    end

    def delete(path:)
      @backend.delete(path: path)
    end

    def download(path:)
      CommunicatorBackend::Encoder.decode(@backend.download(path: path))
    end

    def exists?(path:)
      @backend.exists?(path: path)
    end

    def list(path:)
      @backend.list(path: path)
    end

    def upload(path:, metadata:, payload:)
      @backend.upload(path: path,
                      payload: CommunicatorBackend::Encoder.encode(metadata: metadata, payload: payload))
    end
  end
end
