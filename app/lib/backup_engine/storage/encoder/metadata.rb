require 'pathname'

module BackupEngine
  module Storage
    module Encoder
      class Metadata
        VERSION = 0
      
        def initialize(backup_host:, communicator:)
          @backup_host = backup_host
          @communicator = communicator
          @stamp = Time.now.to_i
        end
      
        def create_file_backup_entry(path:, checksum:, stat:, block_map:)
          upload(path: path,
                 payload: {
                   version: VERSION,
                   stamp: @stamp,
                   type: :file,
                   checksum: checksum,
                   stat: stat,
                   block_map: block_map
                 })
        end

        def create_directory_backup_entry(path:, stat:)
          upload(path: path,
                 payload: {
                   version: VERSION,
                   stamp: @stamp,
                   type: :directory,
                   stat: stat
                 })
        end
        
        def create_symlink_backup_entry(path:, stat:, target:)
          upload(path: path,
                 payload: {
                   version: VERSION,
                   stamp: @stamp,
                   type: :symlink,
                   stat: stat,
                   target: target
                 })
        end

        private
        
        def path(path)
          "metadata/#{@backup_host}/#{path}/metadata.#{@stamp}.json"
        end

        def upload(path:, payload:)
          @communicator.upload(path: path(path), payload: JSON.dump(payload))
        end
      end
    end
  end
end
