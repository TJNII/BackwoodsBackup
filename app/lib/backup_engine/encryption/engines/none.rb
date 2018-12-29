module BackupEngine
  module Encryption
    module Engines
      class None
        def initialize(communicator:)
        @communicator = communicator
        end

        def exists?(path:)
          @communicator.exists?(path: path)
        end

        def encrypt(path:, payload:, metadata:)
          @communicator.upload(path: path, metadata: metadata, payload: payload)
        end

        def decrypt(path:)
          @communicator.download(path: path)
        end
      end
    end
  end
end
