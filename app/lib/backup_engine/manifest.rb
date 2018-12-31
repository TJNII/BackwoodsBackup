require 'base64'
require 'ostruct'
require 'pathname'

require_relative 'checksums/engine.rb'
require_relative 'compression/engine.rb'

module BackupEngine
  module Manifest
    class DecodeError < StandardError
    end

    class Manifest
      VERSION = 1

      def initialize(backup_host:)
        @backup_host = backup_host.freeze
        @stamp = Time.now.to_i.freeze
        @manifest = {}
      end

      def path
        Pathname.new('manifests').join(@backup_host.to_s).join(@stamp.to_s)
      end

      def upload(checksum_engine:, encryption_engine:, compression_engine:)
        payload = JSON.dump(version: VERSION,
                            stamp: @stamp,
                            host: @backup_host,
                            manifest: @manifest)

        compression_result = compression_engine.compress(payload)
        encryption_engine.encrypt(path: path,
                                  payload: compression_result.payload,
                                  metadata: {
                                    version: VERSION,
                                    length: payload.length,
                                    checksum: checksum_engine.block(payload),
                                    compression: compression_result.metadata
                                  })
      end

      def create_file_backup_entry(path:, checksum:, stat:, block_map:)
        @manifest[_encode_path(path)] = {
          type: :file,
          checksum: checksum,
          stat: stat,
          block_map: block_map
        }
      end

      def create_fifo_backup_entry(path:, stat:)
        @manifest[_encode_path(path)] = {
          type: :fifo,
          stat: stat
        }
      end

      def create_directory_backup_entry(path:, stat:)
        @manifest[_encode_path(path)] = {
          type: :directory,
          stat: stat
        }
      end

      def create_symlink_backup_entry(path:, target:)
        @manifest[_encode_path(path)] = {
          type: :symlink,
          target: target
        }
      end

      private

      def _encode_path(path)
        # base64 encode the paths to avoid problems with incompatible filename encodings (UTF-8 vs ASCII-8BIT)
        Base64.encode64(path.to_s)
      end
    end

    # TODO: Very similar to block_encoder restore
    def self.download(path:, encryption_engine:)
      decrypted_data = encryption_engine.decrypt(path: path)
      raise(DecodeError, "Metadata version mismatch: #{decrypted_data[:metadata][:version]}:#{METADATA_VERSION}") if decrypted_data[:metadata][:version] != Manifest::VERSION

      data = BackupEngine::Compression::Engine.decompress(metadata: decrypted_data[:metadata][:compression], payload: decrypted_data[:payload])
      BackupEngine::Checksums::Engine.parse(decrypted_data[:metadata][:checksum]).verify_block(data)

      return _load_manifest_json(data)
    rescue BackupEngine::Checksums::ChecksumMismatch => e
      raise(DecodeError, "Manifest Checksum Mismatch: #{e}")
    rescue BackupEngine::Compression::DecompressionLengthMismatch => e
      raise(DecodeError, "Manifest length mismatch: #{e}")
    end

    def self._load_manifest_json(raw_json)
      json_hash = JSON.parse(raw_json)

      # Manifest requires special handling
      ret_val = OpenStruct.new(json_hash.reject { |k| k == 'manifest' })
      ret_val.manifest = {}

      json_hash['manifest'].each_pair do |b64_path, payload|
        ret_val.manifest[Base64.decode64(b64_path)] = OpenStruct.new(payload)
        ret_val.manifest[Base64.decode64(b64_path)].stat = OpenStruct.new(payload['stat'])
      end

      puts ret_val
      return ret_val.freeze
    end
  end
end
