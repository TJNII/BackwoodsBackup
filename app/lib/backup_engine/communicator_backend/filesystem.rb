require 'pathname'
require 'fileutils'

module BackupEngine
  module CommunicatorBackend
    class Filesystem
      def initialize(base_path:)
        @base_path = Pathname.new(base_path).freeze
        raise('base path does not exist') unless @base_path.directory?
      end

      def date(path:)
        File.stat(@base_path.join(path)).ctime
      end

      def delete(path:)
        FileUtils.rm_rf(@base_path.join(path))
      end

      def download(path:)
        File.read(@base_path.join(path))
      end

      def exists?(path:)
        File.exist?(@base_path.join(path))
      end

      def list(path:, depth: 1)
        raise('Illegal depth') if depth <= 0

        child_paths = @base_path.join(path).children(false).sort.map { |child| path.join(child) }
        return child_paths if depth == 1

        return child_paths.map { |child_path| list(path: child_path, depth: (depth - 1)) }.flatten
      end

      def upload(path:, payload:)
        full_path = @base_path.join(path)
        FileUtils.mkdir_p(full_path.dirname) unless full_path.dirname.directory?
        File.write(full_path, payload)
      end
    end
  end
end
