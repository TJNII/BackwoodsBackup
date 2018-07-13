module BackupClient
  module UploadAPI
    class S3communicator
      def initialize(bucket:)
        raise("STUBBED")
      end

      def upload(path:, payload:)
        raise("STUBBED")
      end

      def exists?(path:)
        raise("STUBBED")
      end

      def download(path:)
        raise("STUBBED")
      end
    end

    class Block
      VERSION = 0

      def initialize(communicator:)
        @communicator = communicator
      end

      def exists?(unencrypted_checksum:, unencrypted_length:)
        @communicator.exists?(upload_metadata_path(unencrypted_checksum: unencrypted_checksum, unencrypted_length: unencrypted_length))
      end

      def back_up_block(encrypted_data:, encrypted_checksum:, unencrypted_checksum:, unencrypted_length:)
        data_path = upload_data_path(unencrypted_checksum: unencrypted_checksum, unencrypted_length: unencrypted_length)
        @communicator.upload(path: data_path,
                             payload: encrypted_data)

        @communicator.upload(path: upload_metadata_path(unencrypted_checksum: unencrypted_checksum, unencrypted_length: unencrypted_length),
                             payload: {
                               version: VERSION,
                               data_path: data_path,
                               encrypted_checksum: encrypted_checksum.to_json,
                               encrypted_length: encrypted_data.length,
                               unencrypted_checksum: unencrypted_checksum.to_json,
                               unencrypted_length: unencrypted_length
                             })
      end
      
      private
      
      def upload_base_path(unencrypted_checksum:, unencrypted_length:)
        Pathname.new("blocks/#{unencrypted_checksum:}/#{unencrypted_length}")
      end

      def upload_metadata_path(unencrypted_checksum:, unencrypted_length:)
        upload_path(unencrypted_checksum: unencrypted_checksum, unencrypted_length: unencrypted_length).join("metadata.json")
      end

      def upload_data_path(unencrypted_checksum:, unencrypted_length:)
        upload_path(unencrypted_checksum: unencrypted_checksum, unencrypted_length: unencrypted_length).join("data")
      end
    end
        
        
    class Metadata
      VERSION = 0
      
      def initialize(backup_host:, communicator:)
        @backup_host = backup_host
        @communicator = communicator
      end
      
      def create_file_backup_entry(path:, checksum:, stat:, block_map:)
        @communicator.upload(path: upload_path(path),
                             payload: {
                               version: VERSION,
                               type: :file,
                               checksum: checksum,
                               stat: stat.to_json,
                               block_map: block_map.to_json
                             })
      end

      def create_directory_backup_entry(path:, stat:)
        @communicator.upload(path: upload_path(path),
                             payload: {
                               version: VERSION,
                               type: :directory,
                               stat: stat.to_json
                             })
      end

      def create_symlink_backup_entry(path:, stat:, target:)
        @communicator.upload(path: upload_path(path),
                             payload: {
                               version: VERSION,
                               type: :symlink,
                               stat: stat.to_json,
                               target: target
                             })
      end
      
      private

      def upload_path(path)
        "metadata/#{@backup_host}/#{path}.json"
      end
    end
  end
end
