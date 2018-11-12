require 'pathname'
require 'fileutils'

module BackupEngine
  module CommunicatorBackend
    class S3
      def initialize(bucket:)
        raise("STUBBED")
      end

      def upload(path:, payload:)
        raise("STUBBED")
      end

      def exists?(path:)
        raise("STUBBED")
      end

      def download(path:)
        raise("STUBBED")
      end
    end
  end
end
