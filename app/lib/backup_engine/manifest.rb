require 'pathname'

module BackupEngine
  module Manifest
    class DecodeError < StandardError
    end

    class Manifest
      VERSION = 0

      def initialize(backup_host:)
        @backup_host = backup_host.freeze
        @stamp = Time.now.to_i.freeze
        @manifest = {}
      end
    
      def path
        Pathname.new("manifests").join(@backup_host.to_s).join(@stamp.to_s)
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
        @manifest[path] = {
          type: :file,
          checksum: checksum,
          stat: stat,
          block_map: block_map
        }
      end

      def create_directory_backup_entry(path:, stat:)
        @manifest[path] = {
          type: :directory,
          stat: stat
        }
      end
      
      def create_symlink_backup_entry(path:, target:)
        @manifest[path] = {
          type: :symlink,
          target: target
        }
      end
    end

    # TODO: Very similar to block_encoder restore
    def self.download(path:, encryption_engine:)
      decrypted_data = encryption_engine.decrypt(path: path)
      raise(DecodeError, "Metadata version mismatch: #{decrypted_data[:metadata][:version]}:#{METADATA_VERSION}") if decrypted_data[:metadata][:version] != Manifest::VERSION
      data = BackupEngine::Compression::Engine.decompress(metadata: decrypted_data[:metadata][:compression], payload: decrypted_data[:payload])
      BackupEngine::Checksums::Engine.parse(decrypted_data[:metadata][:checksum]).verify_block(data)

      # TODO: Return object
      # TODO: Restore engine does manifest["manifest"]
      return JSON.parse(data) # TODO: Can't symbolize names due to paths, need objects
    rescue BackupEngine::Checksums::ChecksumMismatch => e
      raise(DecodeError, "Manifest Checksum Mismatch: #{e}")
    rescue BackupEngine::Compression::DecompressionLengthMismatch => e
      raise(DecodeError, "Manifest length mismatch: #{e}")
    end
  end
end
