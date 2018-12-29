require 'digest'
require 'json'

module BackupEngine
  module Checksums
    module Engines
      class SHA256
        def file(path)
          BackupEngine::Checksums::Result.new(checksum: Digest::SHA256.file(path).hexdigest, algorithm: 'sha256')
        end      

        def block(data)
          BackupEngine::Checksums::Result.new(checksum: Digest::SHA256.hexdigest(data), algorithm: 'sha256')
        end
      end
    end
  end
end
