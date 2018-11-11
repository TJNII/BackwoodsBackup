require_relative '../storage/encoder/block.rb'

module BackupEngine
  module Client
    class Block
      attr_reader :length

      def initialize(data:, api_communicator:, checksum_engine:, encryption_engine:)
        @checksum_engine = checksum_engine
        @encryption_engine = encryption_engine

        @data = data.freeze
        @length = data.length
        @checksum = @checksum_engine.block(@data)

        @block_encoder = BackupEngine::Storage::Encoder::Block.new(communicator: api_communicator,
                                                                   unencrypted_checksum: @checksum,
                                                                   unencrypted_length: @length
                                                                   )
      end

      def to_hash
        {
          unencrypted_checksum: @checksum,
          unencrypted_length: @length
        }
      end
      
      def backed_up?
        @block_encoder.exists?
      end

      def metadata_path
        @block_encoder.metadata_path
      end

      def back_up
        encrypted_data = @encryption_engine.encrypt(@data)
        encrypted_checksum = @checksum_engine.block(encrypted_data.payload)

        @block_encoder.back_up_block(encrypted_data: encrypted_data,
                                     encrypted_checksum: encrypted_checksum)
      end
    end
  end
end
