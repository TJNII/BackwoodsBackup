require_relative 'communicator_backend/filesystem.rb'
require_relative 'communicator_backend/s3.rb'
require_relative 'communicator_backend/encoder.rb'

module BackupEngine
  class Communicator
    def initialize(type:, backend_config:)
      @backend = case type
                 when 'filesystem'
                   CommunicatorBackend::Filesystem.new(backend_config)
                 when 's3'
                   CommunicatorBackend::S3.new(backend_config)
                 else
                   raise("Unknown communicator type #{type}")
                 end
    end

    def upload(path:, payload:, checksum:, checksum_engine:, encryption_engine:, compression_engine:)
      @backend.upload(path: path,
                      payload: CommunicatorBackend::Encoder.encode(payload: payload, 
                                                                   checksum: checksum, 
                                                                   checksum_engine: checksum_engine, 
                                                                   encryption_engine: encryption_engine, 
                                                                   compression_engine: compression_engine))
    end

    def exists?(path:)
      @backend.exists?(path: path)
    end

    def download(path:)
      CommunicatorBackend::Encoder.decode(@backend.download(path: path))
    end
  end
end
