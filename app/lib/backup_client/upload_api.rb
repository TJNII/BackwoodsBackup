require 'pathname'
require 'fileutils'

module BackupClient
  module UploadAPI
    class S3communicator
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

    class FilesystemCommunicator
      def initialize(base_path:)
        @base_path = Pathname.new(base_path).freeze
        raise("base path does not exist") unless @base_path.directory?
      end

      def upload(path:, payload:)
        full_path = @base_path.join(path)
        FileUtils.mkdir_p(full_path.dirname) unless full_path.dirname.directory?
        File.write(full_path, payload)
      end

      def exists?(path:)
        File.exists?(@base_path.join(path))
      end

      def download(path:)
        File.read(@base_path.join(path))
      end
    end
  end
end
