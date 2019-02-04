require 'bindata'

require_relative '../checksums/engine.rb'

module BackupEngine
  module CommunicatorBackend
    module Encoder
      METADATA_CHECKSUM_ALGORITHM = 'sha256'.freeze

      class DecodeError < StandardError
      end

      class VerifyError < StandardError
      end

      class VersionRecord < BinData::Record
        endian :big
        int8   :version
      end

      class V0Record < BinData::Record
        endian :big
        int8   :version

        int16  :metadata_checksum_length, value: lambda { metadata_checksum.length }
        string :metadata_checksum, read_length: :metadata_checksum_length

        int16  :metadata_length, value: lambda { metadata.length }
        string :metadata, read_length: :metadata_length

        int16  :payload_encoding_length, value: lambda { payload_encoding.length }
        string :payload_encoding, read_length: :payload_encoding_length

        int32  :payload_length, value: lambda { payload.length }
        string :payload, read_length: :payload_length
      end

      class V1Record < BinData::Record
        endian :big
        int8   :version

        int16  :metadata_checksum_length, value: lambda { metadata_checksum.length }
        string :metadata_checksum, read_length: :metadata_checksum_length

        int16  :metadata_length, value: lambda { metadata.length }
        string :metadata, read_length: :metadata_length

        int16  :payload_encoding_length, value: lambda { payload_encoding.length }
        string :payload_encoding, read_length: :payload_encoding_length

        int32  :payload_length, value: lambda { payload.length }
        string :payload, read_length: :payload_length

        int16  :payload_checksum_length, value: lambda { payload_checksum.length }
        string :payload_checksum, read_length: :payload_checksum_length
      end

      def self.encode(metadata:, payload:)
        raw_metadata = JSON.dump(metadata)
        V1Record.new(version: 1,
                     metadata_checksum: BackupEngine::Checksums::Engines::SHA256.new.block(raw_metadata),
                     metadata: raw_metadata,
                     payload_encoding: payload.encoding.to_s,
                     payload: payload,
                     payload_checksum: BackupEngine::Checksums::Engines::SHA256.new.block(payload)).to_binary_s
      end

      def self.decode(payload, verify_payload_checksum:)
        version_record = VersionRecord.read(payload)
        record = case version_record.version
                 when 0
                   V0Record.read(payload)
                 when 1
                   V1Record.read(payload)
                 else
                   raise(DecodeError, "Record Version Mismatch: Unknown version #{record.version}")
                 end

        begin
          BackupEngine::Checksums::Engine.parse(record.metadata_checksum.to_s).verify_block(record.metadata)
        rescue BackupEngine::Checksums::ChecksumMismatch => e
          raise(VerifyError, "Record metadata checksum mismatch: #{e}")
        rescue StandardError => e
          raise(VerifyError, "Failed to verify metadata checksum: Exception: #{e.class}: #{e}")
        end

        metadata = JSON.parse(record.metadata, symbolize_names: true)
        decoded_payload = record.payload.force_encoding(record.payload_encoding) # https://github.com/dmendel/bindata/wiki/FAQ#how-do-i-use-string-encodings-with-bindata

        # This path is intended for cleaner consistency check operations as the checksums at the backup block level make this check redundant
        if verify_payload_checksum
          raise(VerifyError, "Cannot verify blocks: No payload metadata in v#{record.version} encoded blocks") if record.version < 1

          begin
            BackupEngine::Checksums::Engine.parse(record.payload_checksum.to_s).verify_block(decoded_payload)
          rescue BackupEngine::Checksums::ChecksumMismatch => e
            raise(VerifyError, "Record payload checksum mismatch: #{e}")
          rescue StandardError => e
            raise(VerifyError, "Failed to verify payload checksum: Exception: #{e.class}: #{e}")
          end
        end

        return { metadata: metadata, payload: decoded_payload }
      end
    end
  end
end
