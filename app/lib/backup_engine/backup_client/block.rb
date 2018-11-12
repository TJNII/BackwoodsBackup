module BackupEngine
  module BackupClient
    class Block
      attr_reader :length, :compression_percent

      def initialize(data:, communicator:, checksum_engine:, encryption_engine:, compression_engine:)
        @communicator = communicator
        @checksum_engine = checksum_engine
        @encryption_engine = encryption_engine
        @compression_engine = compression_engine

        @data = data.freeze
        @length = data.length
        @checksum = @checksum_engine.block(@data)
      end

      def path
        Pathname.new("blocks/#{@checksum}/#{@length}/record.bin")
      end

      def backed_up?
        @communicator.exists?(path: path)
      end

      def back_up
        @communicator.upload(path: path,
                             payload: @data,
                             checksum: @checksum,
                             checksum_engine: @checksum_engine,
                             encryption_engine: @encryption_engine,
                             compression_engine: @compression_engine)
      end
    end
  end
end
