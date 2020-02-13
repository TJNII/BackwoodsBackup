require 'base64'
require 'ostruct'
require 'pathname'

require_relative 'checksums/engine.rb'
require_relative 'compression/engine.rb'

module BackupEngine
  module Manifest
    MANIFESTS_PATH = Pathname.new('manifests').freeze

    class DecodeError < StandardError
    end

    class Manifest
      VERSION = 0

      attr_accessor :partial

      def initialize(host:, set_name:, logger:, metadata_config: nil)
        @host = host.freeze
        @set_name = set_name.freeze
        @stamp = Time.now.to_i.freeze
        @manifest = {}
        @partial = false
        @logger = logger

        # Config stored in the metadata, such as excluded paths
        @metadata_config = metadata_config
      end

      def path
        MANIFESTS_PATH.join(@host.to_s).join(@set_name.to_s).join(@stamp.to_s)
      end

      def upload(checksum_engine:, encryption_engine:, compression_engine:)
        payload = JSON.dump(version: VERSION,
                            stamp: @stamp,
                            host: @host,
                            partial: @partial,
                            config: @metadata_config,
                            manifest: @manifest)

        compression_result = compression_engine.compress(payload)
        @logger.debug("Manifest length: #{payload.length} Compressed #{compression_result.compression_percent}%")

        encryption_engine.encrypt(path: path,
                                  payload: compression_result.payload,
                                  metadata: {
                                    version: VERSION,
                                    length: payload.length,
                                    checksum: checksum_engine.block(payload),
                                    compression: compression_result.metadata
                                  })
        if @partial
          @logger.warn("Uploaded incomplete manifest to #{path}")
        else
          @logger.info("Uploaded manifest to #{path}")
        end
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
      raise(DecodeError, "Metadata version mismatch: #{decrypted_data[:metadata][:version]}:#{Manifest::VERSION}") if decrypted_data[:metadata][:version] != Manifest::VERSION

      data = BackupEngine::Compression::Engine.decompress(metadata: decrypted_data[:metadata][:compression], payload: decrypted_data[:payload])
      BackupEngine::Checksums::Engine.parse(decrypted_data[:metadata][:checksum]).verify_block(data)

      return _load_manifest_json(data)
    rescue BackupEngine::Checksums::ChecksumMismatch => e
      raise(DecodeError, "Manifest Checksum Mismatch: #{e}")
    rescue BackupEngine::Compression::DecompressionLengthMismatch => e
      raise(DecodeError, "Manifest length mismatch: #{e}")
    end

    def self.list_manifest_backups(communicator:)
      return communicator.list(path: MANIFESTS_PATH, depth: 3)
    rescue Errno::ENOENT
      return []
    end

    def self.list_manifest_hosts(communicator:)
      return communicator.list(path: MANIFESTS_PATH)
    rescue Errno::ENOENT
      return []
    end

    def self.list_manifest_sets(communicator:)
      return communicator.list(path: MANIFESTS_PATH, depth: 2)
    rescue Errno::ENOENT
      return []
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

      return ret_val.freeze
    end
  end
end
