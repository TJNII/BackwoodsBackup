require_relative '../pathname.rb'

module BackupEngine
  module CommunicatorBackend
    class S3ListCacheError < StandardError
    end

    # Raise Errno::ENOENT on unknown keys to match Pathname .children errors

    # This object stores an index of objects in S3 and their dates
    class S3ListCache
      attr_reader :date

      def initialize(initial_date: 0)
        @initial_date = initial_date.freeze
        @date = @initial_date
        @cache = {}
      end

      def [](path)
        _by_array_wrapper(path: path) { |path_array| lookup_by_array(path_array: path_array) }
      end

      def add(path:, date:)
        _by_array_wrapper(path: path) { |path_array| add_by_array(path_array: path_array, date: date) }
      end

      def add_by_array(path_array:, date:)
        @date = date if date > @date

        return if path_array.empty?

        @cache[path_array[0]] = S3ListCache.new(initial_date: @initial_date) unless @cache.key?(path_array[0])
        @cache[path_array[0]].add_by_array(path_array: path_array[1..-1], date: date)
      end

      # Direct cache read, intended for testing & internal use
      def cache
        @cache.clone.freeze
      end

      def exists?(path:)
        _by_array_wrapper(path: path) { |path_array| exists_by_array?(path_array: path_array) }
      end

      def exists_by_array?(path_array:)
        return true if path_array.empty? # self
        return false unless @cache.key? path_array[0]

        return @cache[path_array[0]].exists_by_array?(path_array: path_array[1..-1])
      end

      def children(path:)
        _by_array_wrapper(path: path) { |path_array| children_by_array(path_array: path_array) }
      end

      def children_by_array(path_array:)
        return @cache.keys if path_array.empty?

        raise(Errno::ENOENT, "Unknown path #{path_array.join('/')}") unless @cache.key? path_array[0]

        begin
          return @cache[path_array[0]].children_by_array(path_array: path_array[1..-1])
        rescue Errno::ENOENT
          raise(Errno::ENOENT, "Unknown path #{path_array.join('/')}")
        end
      end

      def delete(path:)
        _by_array_wrapper(path: path) { |path_array| delete_by_array(path_array: path_array) }
      end

      def delete_by_array(path_array:)
        if path_array.empty?
          @cache = {}
          return
        end

        raise(Errno::ENOENT, "Unknown path #{path_array.join('/')}") unless @cache.key? path_array[0]

        begin
          @cache[path_array[0]].delete_by_array(path_array: path_array[1..-1])
        rescue Errno::ENOENT
          raise(Errno::ENOENT, "Unknown path #{path_array.join('/')}")
        end

        # As S3 doesn't have directories the parent will no longer exist if the child is empty
        @cache.delete(path_array[0]) if @cache[path_array[0]].cache.empty?
      end

      def lookup_by_array(path_array:)
        return @date if path_array.empty?
        return @date unless @cache.key? path_array[0]

        return @cache[path_array[0]].lookup_by_array(path_array: path_array[1..-1])
      end

      private

      def _by_array_wrapper(path:)
        path_obj = BackupEngine::Pathname.new(path)
        path_array = path_obj.to_a.map(&:to_s)
        raise(S3ListCacheError, "Error converting #{path} to BackupEngine::Pathname: to_a[0] is not '.'") unless path_array[0] == '.'

        return yield(path_array[1..-1])
      end
    end
  end
end
