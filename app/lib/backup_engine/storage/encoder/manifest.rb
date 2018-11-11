module BackupEngine
  module Storage
    module Encoder
      class Manifest
        VERSION = 0

        def initialize(backup_host:, stamp:, communicator:)
          @backup_host = backup_host.freeze
          @stamp = stamp.freeze
          @communicator = communicator.freeze
          @manifest = {}
        end
        
        def add_path(host_path:, metadata_path:)
          @manifest[host_path] = metadata_path
        end

        def path
          "manifests/#{@backup_host}/#{@stamp}"
        end

        def upload
          @communicator.upload(path: path,
                               payload: JSON.dump(version: VERSION,
                                                  stamp: @stamp,
                                                  host: @backup_host,
                                                  manifest: @manifest))
        end
      end
    end
  end
end

        

                       
