require 'bindata'

require_relative '../checksums/engine.rb'

module BackupEngine
  module CommunicatorBackend
    module Encoder
      VERSION = 1
      METADATA_CHECKSUM_ALGORITHM = "sha256".freeze

      class DecodeError < StandardError
      end

      class Record < BinData::Record
        endian :big
        int8   :version

        int16  :metadata_checksum_length, :value => lambda { metadata_checksum.length }
        string :metadata_checksum, :read_length => :metadata_checksum_length          

        int16  :metadata_length, :value => lambda { metadata.length }
        string :metadata, :read_length => :metadata_length          

        int16  :payload_encoding_length, :value => lambda { payload_encoding.length }
        string :payload_encoding, :read_length => :payload_encoding_length

        int32  :payload_length, :value => lambda { payload.length } 
        string :payload, :read_length => :payload_length
      end

      def self.encode(metadata:, payload:)
        raw_metadata = JSON.dump(metadata)
        Record.new(version: VERSION,
                   metadata_checksum: BackupEngine::Checksums::Engines::SHA256.new.block(raw_metadata),
                   metadata: raw_metadata,
                   payload_encoding: payload.encoding.to_s,
                   payload: payload).to_binary_s
      end

      def self.decode(payload)
        record = Record.read(payload)
        raise(DecodeError, "Record Version Mismatch: #{record.version}:#{VERSION}") if record.version != VERSION
        
        BackupEngine::Checksums::Engine.parse(record.metadata_checksum.to_s).verify_block(record.metadata)
        metadata = JSON.parse(record.metadata, :symbolize_names => true)
        payload = record.payload.force_encoding(record.payload_encoding) # https://github.com/dmendel/bindata/wiki/FAQ#how-do-i-use-string-encodings-with-bindata
        
        return {metadata: metadata, payload: payload}
      rescue BackupEngine::Checksums::ChecksumMismatch => e
        raise(DecodeError, "Record metadata checksum mismatch: #{e}")
      end
    end
  end
end
