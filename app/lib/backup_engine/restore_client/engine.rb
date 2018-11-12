require 'tempfile'
require 'fileutils'

require_relative '../checksums/engine.rb'

module BackupEngine
  module RestoreClient
    class Engine
      def initialize(communicator:, logger:)
        @communicator = communicator
        @logger = logger
      end

      def restore_manifest(manifest_path:, restore_path:)
        manifest = JSON.load(@communicator.download(path: manifest_path))
        raise("Unknown manifest version #{manifest["version"]}") if manifest["version"] != 0

        manifest["manifest"].each_pair do |path, metadata|
          path_obj = Pathname.new(path)
          path_obj = path_obj.relative_path_from(Pathname.new('/')) if path_obj.absolute?
          full_path = restore_path.join(path_obj)

          FileUtils.mkdir_p(full_path.dirname) unless full_path.dirname.directory?

          case metadata["type"]
          when "file"
            _restore_file(path: full_path, metadata: metadata)
          when "directory"
            _restore_directory(path: full_path, metadata: metadata)
          when "symlink"
            _restore_symlink(path: full_path, metadata: metadata)
          else
            raise("Unknown file type #{type} for #{path}")
          end
        end
      end

      private

      def _set_attributes(path:, metadata:)
        FileUtils.chmod(metadata["stat"]["mode"], path)
        FileUtils.chown(metadata["stat"]["uid"], metadata["stat"]["gid"], path)
      end

      def _restore_file(path:, metadata:)
        Tempfile.create('restore_client') do |tmpfile| # TODO: configurable path
          FileUtils.chmod(0600, tmpfile.path)

          offset = tmpfile.tell
          metadata["block_map"].each do |block_metadata|
            raise("Restore Error: #{path}: offset mismatch: #{offset}:#{block_metadata["offset"]}") if offset != block_metadata["offset"]
            tmpfile.write(@communicator.download(path: block_metadata["path"]))
            offset = tmpfile.tell
            @logger.debug("#{path}: Restored #{offset}/#{metadata["stat"]["size"]} bytes")
          end

          tmpfile.close
          
          raise("Restore Error: #{path}: Size mismatch: #{File.size(tmpfile.path)}:#{metadata["stat"]["size"]}") if File.size(tmpfile.path) != metadata["stat"]["size"]
          checksum = BackupEngine::Checksums::Engine.new(metadata["checksum"]["algorithm"]).file(tmpfile.path)
          raise("Restore Error: #{path}: Checksum mismatch: #{checksum}:#{metadata["checksum"]}") if checksum != metadata["checksum"]
      
          _set_attributes(path: tmpfile.path, metadata: metadata)
          FileUtils.mv(tmpfile.path, path)
          @logger.info("#{path}: Restored")
        end
      end                          
    
      def _restore_directory(path:, metadata:)
        FileUtils.mkdir(path)
        _set_attributes(path: path, metadata: metadata)
        @logger.info("#{path}: Restored")
      end

      def _restore_symlink(path:, metadata:)
        FileUtils.ln_s(metadata.fetch("target"), path)
        @logger.info("#{path}: Restored")
      end
    end
  end
end