require_relative '../pathname.rb'

module BackupEngine
  module CommunicatorBackend
    class S3ListCacheError < StandardError
    end

    # Raise Errno::ENOENT on unknown keys to match Pathname .children errors

    # This object stores an index of objects in S3 and their dates
    class S3ListCache
      def initialize
        @cache = {}
      end

      def add(path:, date:)
        path_obj = _sanitize_path(path: path)
        ([path_obj] + path_obj.fully_qualified_parent_directories).each do |sub_path_obj|
          next if @cache[sub_path_obj.to_s].to_f >= date

          @cache[sub_path_obj.to_s] = date
        end
      end

      # Direct cache read, intended for testing & internal use
      def cache
        @cache.clone.freeze
      end

      def exists?(path:)
        @cache.key?(_sanitize_path(path: path).to_s)
      end

      def children(path:)
        path_obj = _sanitize_path(path: path)
        raise(Errno::ENOENT, "Unknown path #{path}") unless exists?(path: path_obj)

        path_str = path_obj.to_s
        path_str_end = path_str.length - 1

        if path_str == BackupEngine::Pathname::SEPARATOR
          matching_paths = @cache.keys
        else
          matching_paths = @cache.keys.select { |cache_path| cache_path.length > path_str.length && cache_path[0..path_str_end] == path_str }
          matching_paths.map! { |cache_path| cache_path[(path_str.length)..-1] } # Strip parent path
        end

        # Only return 1st level children, like Pathname .children
        return matching_paths.map { |cache_path| cache_path.split(BackupEngine::Pathname::SEPARATOR)[1] }.compact.uniq
      end

      def date(path:)
        path_obj = _sanitize_path(path: path)
        raise(Errno::ENOENT, "Unknown path #{path}") unless exists?(path: path_obj)

        return @cache[path_obj.to_s]
      end

      def delete(path:)
        path_obj = _sanitize_path(path: path)
        raise(Errno::ENOENT, "Unknown path #{path}") unless exists?(path: path_obj)

        path_str = path_obj.to_s
        path_str_end = path_str.length - 1
        @cache.delete_if { |cache_path, _| cache_path.length >= path_str.length && cache_path[0..path_str_end] == path_str }

        # As S3 doesn't have directories the parent will no longer exist if the child is empty
        path_obj.fully_qualified_parent_directories.reverse_each do |parent_path_obj|
          next unless exists?(path: parent_path_obj)
          break unless children(path: parent_path_obj).empty?

          @cache.delete(parent_path_obj.to_s)
        end
      end

      private

      def _sanitize_path(path:)
        return BackupEngine::Pathname.new('/').join(path)
      end
    end
  end
end
