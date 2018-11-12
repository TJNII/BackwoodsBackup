require 'pathname'

module BackupEngine
  module BackupClient
    class Manifest
      VERSION = 0

      def initialize(backup_host:)
        @backup_host = backup_host.freeze
        @stamp = Time.now.to_i.freeze
        @manifest = {}
      end
    
      def path
        "manifests/#{@backup_host}/#{@stamp}/manifest.bin"
      end
      
      def upload(communicator:, checksum_engine:, encryption_engine:, compression_engine:)
        payload = JSON.dump(version: VERSION,
                            stamp: @stamp,
                            host: @backup_host,
                            manifest: @manifest)

        communicator.upload(path: path,
                            payload: payload,
                            checksum: checksum_engine.block(payload),
                            checksum_engine: checksum_engine,
                            encryption_engine: encryption_engine,
                            compression_engine: compression_engine)
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
  end
end
