require 'json'
require 'redis'

module BackupEngine
  # This class is a wrapper around Redis Hashes with a hash-wide TTL designed to mimic Hash
  # It stores values as JSON blobs to let the JSON library handle object serialization.
  class RedisHash
    include Enumerable

    def initialize(redis_communicator:, redis_path:, ttl:, &block)
      @redis = redis_communicator
      @path = redis_path
      @load_block = block
      @ttl = ttl
    end

    def [](key)
      raw_value = @redis.hget(@path, key)
      # NOTE: Due to the JSON encoding a nil get response is equivalent to no key
      return JSON.parse(raw_value) unless raw_value.nil?
      return nil if @load_block.nil?

      return @load_block.call(self, key)
    end

    def []=(key, value)
      @redis.hset(@path, key, JSON.dump(value))
      _set_ttl
    end

    def clear
      @redis.unlink(@path)
      return self
    end

    # WARNING: Deviation from Hash as this does not return the deleted value
    def delete(key)
      @redis.hdel(@path, key)
      return nil
    end

    # WARNING: Deviation from hash: Does not support enumerator use
    def delete_if
      each_pair do |key, value|
        delete(key) if yield(key, value)
      end
      return nil
    end

    def each_pair
      cursor = 0
      loop do
        cursor, values = @redis.hscan(@path, cursor)
        values.to_h.each_pair do |key, raw_value|
          yield(key, JSON.parse(raw_value))
        end
        return if cursor.to_s == '0'
      end
    end

    def each
      each_pair do |key, value|
        yield([key, value])
      end
    end

    def empty?
      length <= 0
    end

    def fetch(key, *args)
      raise(ArgumentError, "wrong number of arguments (given #{args.length + 1}, expected 1..2)") if args.length > 1

      raw_value = @redis.hget(@path, key)
      return JSON.parse(raw_value) unless raw_value.nil?
      return args[0] if args.length == 1

      raise(KeyError, "key not found: #{key}")
    end

    def key?(key)
      @redis.hexists(@path, key)
    end

    def keys
      @redis.hkeys(@path)
    end

    def length
      @redis.hlen(@path)
    end

    def merge!(other)
      raw_other = other.map { |key, value| [key, JSON.dump(value)] }
      @redis.hmset(@path, *raw_other)
      _set_ttl
      return self
    end

    def ttl
      @redis.ttl(@path)
    end

    def values
      @redis.hvals(@path).map { |value| JSON.parse(value) }
    end

    private

    def _set_ttl
      # Cache if the TTL has been confirmed already
      # This is done to prevent a ttl call per key set, which adds ~60s/1000000keys
      return if @ttl_ok

      current_ttl = ttl
      return if current_ttl > 0 && current_ttl < @ttl

      @redis.expire(@path, @ttl)
      @ttl_ok = true
    end
  end
end
