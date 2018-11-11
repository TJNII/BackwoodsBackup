require 'pathname'

require_relative 'manifest.rb'

module BackupEngine
  module Storage
    module Encoder
      class Metadata
        VERSION = 0
      
        attr_reader :manifest

        def initialize(backup_host:, communicator:)
          @backup_host = backup_host
          @communicator = communicator
          @stamp = Time.now.to_i
          @manifest = Manifest.new(backup_host: @backup_host, stamp: @stamp, communicator: @communicator)
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
        
        def create_symlink_backup_entry(path:, target:)
          upload(path: path,
                 payload: {
                   version: VERSION,
                   stamp: @stamp,
                   type: :symlink,
                   target: target
                 })
        end

        private
        
        def path(path)
          "metadata/#{@backup_host}/#{path}/metadata.#{@stamp}.json"
        end

        def upload(path:, payload:)
          force_encoded_path = path.to_s.force_encoding('UTF-8')
          metadata_path = path(force_encoded_path)
          @communicator.upload(path: metadata_path, payload: JSON.dump(payload))
          @manifest.add_path(host_path: force_encoded_path, metadata_path: metadata_path)
        end
      end
    end
  end
end
