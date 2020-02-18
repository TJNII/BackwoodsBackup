require 'connection_pool'
require 'powerpack/hash'
require 'redis'
require_relative '../multi_threading.rb'
require_relative '../pathname.rb'
require_relative '../redis_hash.rb'

module BackupEngine
  module CommunicatorBackend
    class S3ListCacheError < StandardError
    end

    # Raise Errno::ENOENT on unknown keys to match Pathname .children errors

    # This object stores an index of objects in S3 and their dates
    # It takes a block that will be called to seed the cache is the cache is empty
    # NOTE: Cache seeding was written with Redis TTLs in mind where the entire hash will expire.
    #  Having the entire hash expire is useful as then there is no negative TTL handling required
    #  As such the non-[] methods are avoided on the @cache object to ensure the default hash handler
    #  is called on empty cache.
    class S3ListCache
      def initialize(id:, logger:, type: 'memory', ttl: 2592000, redis_config: {}, &block)
        @seed_block = block
        @logger = logger
        @index_lock = Mutex.new
        @seed_lock = Mutex.new

        case type
        when 'memory'
          @cache = Hash.new { |h, k| _cache_default_handler(h, k) }
        when 'redis'
          redis_communicator = ConnectionPool::Wrapper.new(size: BackupEngine::MultiThreading::PROCESSOR_COUNT, timeout: redis_config.symbolize_keys.fetch(:timeout, 5)) { Redis.new(redis_config.symbolize_keys) }
          @cache = BackupEngine::RedisHash.new(redis_communicator: redis_communicator,
                                               redis_path: "BackwoodsBackup/BackupEngine/CommunicatorBackend/S3ListCache/#{id}",
                                               ttl: ttl) { |h, k| _cache_default_handler(h, k) }
        else
          raise(ArgumentError, "Unknown cache type #{cache_type}")
        end
      end

      def add(path:, date:)
        _invalidate_index # Invalidate the index as it must be sorted rather than try and inject at the right index
        path_obj = _sanitize_path(path: path)
        @index_lock.synchronize do
          ([path_obj] + path_obj.fully_qualified_parent_directories.reverse).each do |sub_path_obj|
            break if @cache.fetch(sub_path_obj.to_s, 0).to_f >= date

            @cache[sub_path_obj.to_s] = date
          end
        end
      end

      # Direct cache read, intended for testing & internal use
      def cache
        @cache.to_h.clone.freeze
      end

      def children(path:, depth: 1, fully_qualified: false)
        path_obj = _sanitize_path(path: path)
        raise(Errno::ENOENT, "Unknown path #{path}") unless exists?(path: path_obj)
        raise(ArgumentError, "Illegal Depth #{depth} for path #{path}") if depth < -1

        path_str = path_obj.to_s

        # Loading the keys into a sorted index and using bsearch() is many orders of magnatude faster than curser based linear searches
        # This can also be done with a Redis sorted set using zrangebylex
        # Using an in-memory array as it's compatible with in-memory caches, relatively performant, and skirts TTL problems.

        if path_str == BackupEngine::Pathname::SEPARATOR
          matching_paths = index[1..-1]
        else
          @index_lock.synchronize do
            index_start = _index.bsearch_index { |k| path_str <=> k }
            raise("INTERNAL ERROR: Failed to locate index of #{path_str}") if index_start.nil?

            index_start += 1 # Increment +1 to start at first sub path

            # Find the end via a linear search.  bsearch returns "a value from this array" which is no good for finding the exact end
            path_str_with_sep = path_obj.to_s + BackupEngine::Pathname::SEPARATOR
            path_str_with_sep_end = path_str_with_sep.length - 1

            index_length = _index(must_cache: true)[index_start..-1].find_index { |k| k[0..path_str_with_sep_end] != path_str_with_sep }
            return [] if index_length == 0

            index_end = index_length.nil? ? -1 : (index_start + index_length - 1)
            matching_paths = _index(must_cache: true)[index_start..index_end]
          end
        end

        unless depth < 0
          separator_depth = depth + path_obj.to_a.length - 1
          matching_paths.select! { |child_path| child_path.count(BackupEngine::Pathname::SEPARATOR) == separator_depth }
        end

        cut_index = path_str == BackupEngine::Pathname::SEPARATOR ? 1 : (path_str.length + 1)

        return matching_paths.map! { |cache_path| BackupEngine::Pathname.new(path).join(cache_path[cut_index..-1]) } if fully_qualified

        return matching_paths.map! { |cache_path| BackupEngine::Pathname.new(cache_path[cut_index..-1]) }
      end

      def date(path:)
        ret_val = @cache[_sanitize_path(path: path).to_s]
        return Time.at(ret_val) unless ret_val.nil?

        raise(Errno::ENOENT, "Unknown path #{path}")
      end

      def delete(path:)
        path_obj = _sanitize_path(path: path)
        raise(Errno::ENOENT, "Unknown path #{path}") unless exists?(path: path_obj)

        ([path_obj.to_s] + children(path: path_obj, fully_qualified: true, depth: -1)).each do |tgt_path|
          @cache.delete(tgt_path.to_s)
          _delete_from_index(tgt_path)
        end

        # As S3 doesn't have directories the parent will no longer exist if the child is empty
        path_obj.fully_qualified_parent_directories.reverse_each do |parent_path_obj|
          next unless exists?(path: parent_path_obj)
          break unless children(path: parent_path_obj).empty?

          @cache.delete(parent_path_obj.to_s)
          _delete_from_index(parent_path_obj.to_s)
        end
      end

      def exists?(path:)
        # Don't use .key? as that doesn't trigger the seed block
        !@cache[_sanitize_path(path: path).to_s].nil?
      end

      # Internal index, exposed for testing
      def index
        @index_lock.synchronize do
          _index
        end
      end

      private

      def _cache_default_handler(hash, key)
        @seed_lock.synchronize do
          return nil unless hash.empty?

          _invalidate_index

          begin
            @seed_block.call(self)
          rescue Exception => e # rubocop: disable Lint/RescueException
            # NOTE: This intentionally catches SystemExit and Interrupt to ensure partial caches don't persist in external stores on ctrl-c
            hash.clear
            raise(e)
          end

          hash.fetch(key, nil)
        end
      end

      def _delete_from_index(key)
        raise("INTERNAL ERROR: delete_from_index: Key #{key} not found") if @index&.delete(key.to_s).nil? && !@index.nil?
      end

      def _index(must_cache: false)
        raise('INTERNAL ERROR: NO LOCK') unless @index_lock.owned?
        return @index unless @index.nil?
        raise('RACE: Index invalidated during critical/unrecoverable operation, likely cache TTL timeout') if must_cache

        @logger.info('S3 List Cache: Generating index of paths')
        intermediate_index = @cache.keys
        @logger.debug('S3 List Cache: Sorting index')
        intermediate_index.sort! # Must be sorted for bsearch to work
        @logger.info('S3 List Cache: Index generated')

        @index = intermediate_index
        return intermediate_index
      end

      def _invalidate_index
        @index_lock.synchronize do
          @index = nil
        end
      end

      def _sanitize_path(path:)
        return BackupEngine::Pathname.new('/').join(path)
      end
    end
  end
end
