require 'pathname'

module BackupEngine
  module Storage
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
    end
  end
end
