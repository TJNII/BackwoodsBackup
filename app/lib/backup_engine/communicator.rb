require 'powerpack/hash'

require_relative 'communicator_backend/filesystem.rb'
require_relative 'communicator_backend/s3.rb'
require_relative 'communicator_backend/encoder.rb'

module BackupEngine
  class Communicator
    def initialize(type:, backend_config:, logger:)
      @backend = case type
                 when 'filesystem'
                   CommunicatorBackend::Filesystem.new(**backend_config.symbolize_keys)
                 when 's3'
                   CommunicatorBackend::S3.new(**backend_config.symbolize_keys.merge(logger: logger))
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

    def download(path:, verify_payload_checksum: false)
      CommunicatorBackend::Encoder.decode(@backend.download(path: path), verify_payload_checksum: verify_payload_checksum)
    end

    def exists?(path:)
      @backend.exists?(path: path)
    end

    def list(path:, depth: 1)
      @backend.list(path: path, depth: depth)
    end

    def upload(path:, metadata:, payload:)
      @backend.upload(path: path,
                      payload: CommunicatorBackend::Encoder.encode(metadata: metadata, payload: payload))
    end
  end
end
