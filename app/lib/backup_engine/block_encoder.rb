module BackupEngine
  module BlockEncoder
    METADATA_VERSION = 0

    class BlockError < StandardError
    end
    
    class Block
      attr_reader :length, :data, :compression_percent

      def initialize(data:, checksum_engine:, encryption_engine:)
        @checksum_engine = checksum_engine
        @encryption_engine = encryption_engine

        @data = data.freeze
        @length = data.length
        @checksum = @checksum_engine.block(@data)
      end

      def path
        Pathname.new("blocks/#{@checksum}/#{@length}")
      end

      def backed_up?
        @encryption_engine.exists?(path: path)
      end

      def back_up(compression_engine:)
        compression_result = compression_engine.compress(@data)
        @encryption_engine.encrypt(path: path,
                                   payload: compression_result.payload,
                                   metadata: {
                                     version: METADATA_VERSION,
                                     length: @length,
                                     checksum: @checksum,
                                     compression: compression_result.metadata
                                   })
        return {compression_percent: compression_result.compression_percent}
      end

      def verify(length:, checksum:)
        raise(BlockError, "Block length mismatch: #{@length}:#{length}") if length != @length
        raise(BlockError, "Block Checksum Mismatch: #{@checksum}:#{checksum}") if checksum != @checksum
      end
    end

    def self.restore(path:, encryption_engine:)
      decrypted_data = encryption_engine.decrypt(path: path)
      raise(BlockError, "Metadata version mismatch: #{decrypted_data[:metadata][:version]}:#{METADATA_VERSION}") if decrypted_data[:metadata][:version] != METADATA_VERSION
      data = BackupEngine::Compression::Engine.decompress(metadata: decrypted_data[:metadata][:compression], payload: decrypted_data[:payload])
      checksum_engine = BackupEngine::Checksums::Engine.parse(decrypted_data[:metadata][:checksum]).engine

      block = Block.new(data: data,
                        checksum_engine: checksum_engine,
                        encryption_engine: encryption_engine)

      block.verify(length: decrypted_data[:metadata][:length],
                   checksum: decrypted_data[:metadata][:checksum])
      
      return block
    end
  end
end
