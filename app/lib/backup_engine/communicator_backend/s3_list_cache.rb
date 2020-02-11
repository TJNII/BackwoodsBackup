require 'powerpack/hash'
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
      def initialize(id:, type: 'memory', ttl: 2592000, redis_config: {}, &block)
        @seed_block = block

        case type
        when 'memory'
          @cache = Hash.new { |h, k| _cache_default_handler(h, k) }
        when 'redis'
          @cache = BackupEngine::RedisHash.new(redis_communicator: Redis.new(redis_config.symbolize_keys),
                                               redis_path: "BackwoodsBackup/BackupEngine/CommunicatorBackend/S3ListCache/#{id}",
                                               ttl: ttl) { |h, k| _cache_default_handler(h, k) }
        else
          raise(ArgumentError, "Unknown cache type #{cache_type}")
        end
      end

      def add(path:, date:)
        path_obj = _sanitize_path(path: path)
        ([path_obj] + path_obj.fully_qualified_parent_directories.reverse).each do |sub_path_obj|
          break if @cache.fetch(sub_path_obj.to_s, 0).to_f >= date

          @cache[sub_path_obj.to_s] = date
        end
      end

      # Direct cache read, intended for testing & internal use
      def cache
        @cache.to_h.clone.freeze
      end

      def exists?(path:)
        # Don't use .key? as that doesn't trigger the seed block
        !@cache[_sanitize_path(path: path).to_s].nil?
      end

      def children(path:)
        path_obj = _sanitize_path(path: path)
        raise(Errno::ENOENT, "Unknown path #{path}") unless exists?(path: path_obj)

        path_str = path_obj.to_s
        path_str_end = path_str.length - 1

        if path_str == BackupEngine::Pathname::SEPARATOR
          matching_paths = @cache.keys
        else
          matching_paths = []
          # Use each_pair (cursor based with Redis) to avoid loading millions of keys into memory when using remote backed caches
          @cache.each_pair do |cache_path, _|
            next unless cache_path.length > path_str.length && cache_path[0..path_str_end] == path_str

            matching_paths.push(cache_path[(path_str.length)..-1]) # Strip parent path
          end
        end

        # Only return 1st level children, like Pathname .children
        return matching_paths.map { |cache_path| cache_path.split(BackupEngine::Pathname::SEPARATOR)[1] }.compact.uniq
      end

      def date(path:)
        ret_val = @cache[_sanitize_path(path: path).to_s]
        return Time.at(ret_val) unless ret_val.nil?

        raise(Errno::ENOENT, "Unknown path #{path}")
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

      def _cache_default_handler(hash, key)
        return nil unless hash.empty?

        @seed_block.call(self)
        hash.fetch(key, nil)
      end

      def _sanitize_path(path:)
        return BackupEngine::Pathname.new('/').join(path)
      end
    end
  end
end
