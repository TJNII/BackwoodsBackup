require 'bindata'

require_relative '../encryption/engine.rb'
require_relative '../compression/engine.rb'
require_relative '../checksums/engine.rb'

module BackupEngine
  module CommunicatorBackend
    module Encoder
      VERSION = 0

      class DecodeError < StandardError
      end

      class Record < BinData::Record
        endian :big
        int8   :version
        int16  :metadata_length, :value => lambda { metadata.length }
        string :metadata, :read_length => :metadata_length          
        int32  :payload_length, :value => lambda { payload.length } 
        string :payload, :read_length => :payload_length
      end

      def self.encode(payload:, checksum:, checksum_engine:, encryption_engine:, compression_engine:)
        compressed_data = compression_engine.compress(payload)
        encrypted_data = encryption_engine.encrypt(compressed_data.payload)
        encrypted_checksum = checksum_engine.block(encrypted_data.payload)

        # compression_percent = 100 - (compressed_data.length.to_f / @length * 100)

        Record.new(version: VERSION,
                   metadata: JSON.dump(unencrypted_checksum: checksum,
                                       unencrypted_length: payload.length,
                                       compression_metadata: compressed_data.metadata,
                                       encryption_metadata: encrypted_data.metadata,
                                       encrypted_checksum: encrypted_checksum,
                                       payload_encoding: payload.encoding.to_s),
                   payload: encrypted_data.payload).to_binary_s
      end

      def self.decode(payload)
        record = Record.read(payload)
        
        raise(DecodeError, "Record Version Mismatch: #{record.version}:#{VERSION}") if record.version != VERSION
        metadata = JSON.load(record.metadata)

        raise(DecodeError, "Encrypted payload length mismatch: #{record.payload.length}:#{metadata["encrypted_metadata"]["length"]}") if record.payload.length != metadata["encryption_metadata"]["length"]
        encrypted_checksum = BackupEngine::Checksums::Engine.new(metadata["encrypted_checksum"]["algorithm"]).block(record.payload)
        raise(DecodeError, "Encrypted checksum mismatch: #{encrypted_checksum}:#{metadata["encrypted_checksum"]}") if encrypted_checksum != metadata["encrypted_checksum"]

        decryptor = BackupEngine::Encryption::Engine.new(metadata["encryption_metadata"]["algorithm"])
        compressed_data = decryptor.decrypt(record.payload)
        
        raise(DecodeError, "Compressed payload length mismatch: #{compressed_data.length}:#{metadata["compression_metadata"]["length"]}") if compressed_data.length != metadata["compression_metadata"]["length"]
        decompressor = BackupEngine::Compression::Engine.new(metadata["compression_metadata"]["algorithm"])
        data = decompressor.decompress(compressed_data).force_encoding(metadata["payload_encoding"]) # https://github.com/dmendel/bindata/wiki/FAQ#how-do-i-use-string-encodings-with-bindata

        raise(DecodeError, "Payload length mismatch: #{data.length}:#{metadata["unencrypted_length"]}") if data.length != metadata["unencrypted_length"]
        unencrypted_checksum = BackupEngine::Checksums::Engine.new(metadata["unencrypted_checksum"]["algorithm"]).block(data)
        raise(DecodeError, "Unencrypted checksum mismatch: #{unencrypted_checksum}:#{metadata["unencrypted_checksum"]}") if unencrypted_checksum != metadata["unencrypted_checksum"]
        return data
      end
    end
  end
end
