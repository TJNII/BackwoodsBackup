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
          store(path: path,
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
          store(path: path,
                 payload: {
                   version: VERSION,
                   stamp: @stamp,
                   type: :directory,
                   stat: stat
                 })
        end
        
        def create_symlink_backup_entry(path:, target:)
          store(path: path,
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

        def store(path:, payload:)
          metadata_path = path(path)
          @manifest.add_path(host_path: path, metadata: payload)
        end
      end
    end
  end
end
