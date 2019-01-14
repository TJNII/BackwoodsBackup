require_relative '../pathname.rb'

module BackupEngine
  module CommunicatorBackend
    class S3ListCacheError < StandardError
    end

    class S3ListCache
      attr_reader :date

      def initialize(initial_date: 0)
        @initial_date = initial_date.freeze
        @date = @initial_date
        @cache = {}
        @complete = false
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

      # Complete flag: set when path has been fully listed (via mark_complete())
      # Default to self on no path for simplicity/testing
      def complete?(path: nil)
        return @complete if path.nil?

        _by_array_wrapper(path: path) { |path_array| complete_by_array?(path_array: path_array) }
      end

      def complete_by_array?(path_array:)
        return @complete if path_array.empty?
        return false unless @cache.key? path_array[0]

        @cache[path_array[0]].complete_by_array?(path_array: path_array[1..-1])
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
        if path_array.empty?
          raise(S3ListCacheError, "Cannot list #{path_array.join('/')}: Cache incomplete") unless @complete

          return @cache.keys
        end

        raise(S3ListCacheError, "Unknown path #{path_array.join('/')}") unless @cache.key? path_array[0]

        begin
          return @cache[path_array[0]].children_by_array(path_array: path_array[1..-1])
        rescue S3ListCacheError
          raise(S3ListCacheError, "Unknown path #{path_array.join('/')}")
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

        raise(S3ListCacheError, "Unknown path #{path_array.join('/')}") unless @cache.key? path_array[0]

        begin
          @cache[path_array[0]].delete_by_array(path_array: path_array[1..-1])
        rescue S3ListCacheError
          raise(S3ListCacheError, "Unknown path #{path_array.join('/')}")
        end

        # As S3 doesn't have directories the parent will no longer exist if the child is empty
        @cache.delete(path_array[0]) if @cache[path_array[0]].cache.empty?
      end

      def lookup_by_array(path_array:)
        return @date if path_array.empty?
        return @date unless @cache.key? path_array[0]

        return @cache[path_array[0]].lookup_by_array(path_array: path_array[1..-1])
      end

      def mark_complete(path:)
        _by_array_wrapper(path: path) { |path_array| mark_complete_by_array(path_array: path_array) }
      end

      def mark_complete_by_array(path_array:)
        return _complete! if path_array.empty?
        # no-op on unknown key: This is caused by a list for a missing key
        return unless @cache.key? path_array[0]

        @cache[path_array[0]].mark_complete_by_array(path_array: path_array[1..-1])
      rescue S3ListCacheError
        raise(S3ListCacheError, "Unknown path #{path_array.join('/')}")
      end

      private

      def _by_array_wrapper(path:)
        path_obj = BackupEngine::Pathname.new(path)
        path_array = path_obj.to_a.map(&:to_s)
        raise(S3ListCacheError, "Error converting #{path} to BackupEngine::Pathname: to_a[0] is not '.'") unless path_array[0] == '.'

        return yield(path_array[1..-1])
      end

      # Mark this cache and all child caches complete
      def _complete!
        @complete = true
        @cache.values.each do |child|
          child.mark_complete_by_array(path_array: [])
        end
      end
    end
  end
end
