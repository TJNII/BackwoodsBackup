require 'pathname'

module BackupClient
  module Encoder
    class Block
      VERSION = 0

      def initialize(communicator:, unencrypted_checksum:, unencrypted_length:)
        @communicator = communicator
        @unencrypted_checksum = unencrypted_checksum
        @unencrypted_length = unencrypted_length
      end

      def metadata_path
        base_path.join("metadata.json")
      end

      def data_path
        base_path.join("data")
      end

      def exists?
        @communicator.exists?(path: metadata_path)
      end

      def back_up_block(encrypted_data:, encrypted_checksum:)
        @communicator.upload(path: data_path,
                             payload: encrypted_data.payload)

        @communicator.upload(path: metadata_path,
                             payload: JSON.dump(version: VERSION,
                                                data_path: data_path,
                                                encryption_algorithm: encrypted_data.algorithm,
                                                encrypted_checksum: encrypted_checksum,
                                                encrypted_length: encrypted_data.length,
                                                unencrypted_checksum: @unencrypted_checksum,
                                                unencrypted_length: @unencrypted_length)
                             )
      end

      private

      def base_path
        Pathname.new("blocks/#{@unencrypted_checksum}/#{@unencrypted_length}")
      end

    end
        
    class Metadata
      VERSION = 0
      
      def initialize(backup_host:, communicator:)
        @backup_host = backup_host
        @communicator = communicator
        @stamp = Time.now.to_i
      end
      
      def create_file_backup_entry(path:, checksum:, stat:, block_map:)
        upload(path: path,
               payload: {
                 version: VERSION,
                 stamp: @stamp,
                 type: :file,
                 checksum: checksum,
                 stat: stat,
                 block_map: block_map
               })
      end

      def create_directory_backup_entry(path:, stat:)
        upload(path: path,
               payload: {
                 version: VERSION,
                 stamp: @stamp,
                 type: :directory,
                 stat: stat
               })
      end

      def create_symlink_backup_entry(path:, stat:, target:)
        upload(path: path,
               payload: {
                 version: VERSION,
                 stamp: @stamp,
                 type: :symlink,
                 stat: stat,
                 target: target
               })
      end

      private

      def path(path)
        "metadata/#{@backup_host}/#{path}/metadata.#{@stamp}.json"
      end

      def upload(path:, payload:)
        @communicator.upload(path: path(path), payload: JSON.dump(payload))
      end
    end
  end
end
