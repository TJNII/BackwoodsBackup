require_relative '../storage/encoder/block.rb'

module BackupEngine
  module BackupClient
    class Block
      attr_reader :length, :compression_percent

      def initialize(data:, api_communicator:, checksum_engine:, encryption_engine:, compression_engine:)
        @checksum_engine = checksum_engine
        @encryption_engine = encryption_engine
        @compression_engine = compression_engine

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
        compressed_data = @compression_engine.compress(@data)
        @compression_percent = 100 - (compressed_data.length.to_f / @length * 100)
        encrypted_data = @encryption_engine.encrypt(compressed_data.payload)
        encrypted_checksum = @checksum_engine.block(encrypted_data.payload)

        @block_encoder.back_up_block(compression_metadata: compressed_data.metadata,
                                     encrypted_data: encrypted_data,
                                     encrypted_checksum: encrypted_checksum)
      end
    end
  end
end
