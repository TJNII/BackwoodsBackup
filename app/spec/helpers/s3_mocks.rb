module BackupEngineTestHelpers
  # Mock S3 functions used per
  # https://aws.amazon.com/blogs/developer/advanced-client-stubbing-in-the-aws-sdk-for-ruby-version-3/
  # NOTE: Public methods are intended to be used in tests to query the mock state, they are not maps to S3 SDK functions
  class S3Mocks
    def initialize
      @buckets = Hash.new { |h, k| h[k] = {} }
    end

    def delete_object(bucket:, key:)
      @buckets[bucket].delete(key)
    end

    def get_object(bucket:, key:)
      @buckets[bucket].fetch(key, {})
    end

    def object_paths(bucket:)
      @buckets[bucket].keys
    end

    def seed_object(bucket:, key:, body:, last_modified:, storage_class:)
      raise('Body cannot be nil') if body.nil?

      @buckets[bucket][key] = {
        body: body,
        last_modified: last_modified,
        storage_class: storage_class,
        content_length: body.length
      }
    end

    def stub_client(aws_s3_sdk_client:)
      %i[delete_objects get_object list_objects_v2 put_object].each do |operation_name|
        aws_s3_sdk_client.stub_responses(operation_name, ->(context) { method(:"_stub_#{operation_name}").call(context) })
      end
    end

    private

    def _stub_delete_objects(context)
      context.params[:delete][:objects].each do |object_param|
        raise("Attempt to delete non-existent object #{object_param[:key]}") unless @buckets[context.params[:bucket]].key?(object_param[:key])

        @buckets[context.params[:bucket]].delete(object_param[:key])
      end
    end

    def _stub_get_object(context)
      @buckets[context.params[:bucket]].fetch(context.params[:key], 'NoSuchKey')
    end

    def _stub_list_objects_v2(context)
      # TODO: Pagination
      contents = @buckets[context.params[:bucket]].map do |key, object|
        next if !context.params[:prefix].empty? && key !~ /^#{context.params[:prefix]}/

        { key: key,
          last_modified: object[:last_modified] }
      end

      return {
        contents: contents.compact,
        next_continuation_token: nil
      }
    end

    def _stub_put_object(context)
      @buckets[context.params[:bucket]][context.params[:key]] = {
        last_modified: Time.now,
        content_length: context.params[:body].length
      }.merge(context.params.reject { |k, _| %i[bucket key].include?(k) })

      return {}
    end
  end
end
