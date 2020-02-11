require 'aws-sdk-s3'

require_relative '../pathname.rb'
require_relative 's3_list_cache.rb'

module BackupEngine
  module CommunicatorBackend
    class S3CommunicatorError < StandardError
    end

    class S3
      def initialize(logger:, bucket:, s3_client_config:, cache_config: {}, storage_class: 'STANDARD_IA', full_cache_seed: true)
        @logger = logger
        @bucket = bucket.freeze
        @storage_class = storage_class.freeze

        # Do not enforce any required keys as they can all come from ENV vars, AWS config files, etc...
        if s3_client_config.key?('credentials')
          # Reformat credentials into the proper object, because AWS
          s3_client_config['credentials'] = Aws::Credentials.new(s3_client_config['credentials'].fetch('access_key_id'), s3_client_config['credentials'].fetch('secret_access_key'))
        end
        @s3 = Aws::S3::Client.new(s3_client_config.symbolize_keys)

        # Always perform a full cache seed to simplify cache handling, changed in [TODO: VERSION]
        # https://github.com/TJNII/BackwoodsBackup/issues/8
        # full_cache_seed argument is left for reverse compatibility in configs
        raise(S3CommunicatorError, 'full_cache_seed option has been deprecated, see https://github.com/TJNII/BackwoodsBackup/issues/8') unless full_cache_seed

        @cache = S3ListCache.new(cache_config.symbolize_keys.merge(id: bucket)) do |cache|
          @logger.info('Seeding local cache of S3 object paths')
          _s3_list(path: Pathname.new('.'), cache: cache)
          @logger.info('Seeding local cache of S3 object paths complete')
        end
      end

      def date(path:)
        @cache.date(path: path)
      end

      def delete(path:)
        # S3 cannot delete recursively, files must be individually deleted
        # Rather than rebuild from the cache simply re-list the path and multi-delete all the objects within
        list_out = @s3.list_objects_v2(bucket: @bucket, prefix: path.to_s)

        # Simplify for the BackwoodsBackup use case: The cleaner shouldn't delete more than [keys] * 2 files in a shot, so don't bother with pagination
        # If there is an attempt to delete over 1000 files (the pagination limit) then something is probably wrong.
        raise(S3CommunicatorError, "Attempt to delete over #{list_out.contents.length} objects in one request") unless list_out.next_continuation_token.nil?

        if list_out.contents.empty?
          # Missing file, attempting to delete the directory
          raise(S3CommunicatorError, "Cache out of sync for #{path}") if @cache.exists?(path: path)

          return
        end

        @s3.delete_objects(bucket: @bucket, delete: { objects: list_out.contents.map { |c| { key: c.key } } })
        @cache.delete(path: path)
      end

      def download(path:)
        get_response = @s3.get_object(bucket: @bucket, key: path.to_s)
        raise(S3CommunicatorError, "Object length mismatch for #{path}: #{get_response.content_length}:#{get_response.body.length}") if get_response.content_length != get_response.body.length

        return get_response.body.read
      end

      def exists?(path:)
        @cache.exists?(path: path)
      end

      # NOTE: This only returns the next level paths and is intended to behave like a filesystem ls call
      def list(path:)
        @cache.children(path: path).sort.map { |child| path.join(child) }
      end

      def upload(path:, payload:)
        @s3.put_object(bucket: @bucket, key: path.to_s, body: payload, storage_class: @storage_class)
        @cache.add(path: path, date: Time.now.to_f)
      end

      private

      def _cache_add_s3_list_output(contents:, cache:)
        contents.each do |object|
          cache.add(path: object.key, date: object.last_modified.to_f)
        end
      end

      def _s3_list(path:, cache:)
        # This is a cost optimization for the BackwoodsBackup use case.
        # AWS charges per request, so it's cost effective to cast as wide a net as possible and store the results in memory
        # (hence the S3ListCache class)
        # The block shas (2nd level) are too unique, optimizing for them is past the point of diminishing returns
        # However everything within a sha are practical to list in one request
        # This will save cost on key lookups.
        path_array = BackupEngine::Pathname.new(path).to_a.map(&:to_s)
        raise("Error optimizing #{path}: [0] is not '.'") unless path_array[0] == '.'

        list_path = path_array[1..2].join('/')
        list_out = @s3.list_objects_v2(bucket: @bucket, prefix: list_path)
        _cache_add_s3_list_output(contents: list_out.contents, cache: cache)
        until list_out.next_continuation_token.nil?
          @logger.debug('Seeding local cache of S3 object paths: Continuing...')
          list_out = @s3.list_objects_v2(bucket: @bucket, continuation_token: list_out.next_continuation_token)
          _cache_add_s3_list_output(contents: list_out.contents, cache: cache)
        end
      end
    end
  end
end
