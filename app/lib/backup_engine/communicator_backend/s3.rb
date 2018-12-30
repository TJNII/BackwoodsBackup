require 'pathname'
require 'fileutils'

module BackupEngine
  module CommunicatorBackend
    class S3
      # WIP
      # rubocop: disable Lint/UnusedMethodArgument
      def initialize(bucket:)
        raise('STUBBED')
      end

      def upload(path:, payload:)
        raise('STUBBED')
      end

      def exists?(path:)
        raise('STUBBED')
      end

      def download(path:)
        raise('STUBBED')
      end
      # rubocop: enable Lint/UnusedMethodArgument
    end
  end
end
