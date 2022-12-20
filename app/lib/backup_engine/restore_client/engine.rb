require 'tempfile'
require 'fileutils'

require_relative '../block_encoder.rb'
require_relative '../checksums/engine.rb'
require_relative '../manifest.rb'

module BackupEngine
  module RestoreClient
    class Engine
      def initialize(encryption_engine:, logger:)
        @encryption_engine = encryption_engine
        @logger = logger
      end

      def restore_manifest(manifest_path:, restore_path:, target_path_regex:)
        manifest = BackupEngine::Manifest.download(path: manifest_path, encryption_engine: @encryption_engine)
        @logger.debug('Manifest download complete')
        @logger.warn('Manifest is incomplete and will be missing files') if manifest.partial

        _targeted_manifest(manifest: manifest.manifest, target_path_regex: target_path_regex).each_pair do |path_obj, metadata|
          full_path = restore_path.join_relative(path_obj)

          FileUtils.mkdir_p(full_path.dirname) unless full_path.dirname.directory?

          case metadata.type
          when 'file'
            _restore_file(path: full_path, metadata: metadata)
          when 'fifo'
            _restore_fifo(path: full_path, metadata: metadata)
          when 'directory'
            _restore_directory(path: full_path, metadata: metadata)
          when 'symlink'
            _restore_symlink(path: full_path, metadata: metadata)
          else
            raise("Unknown file type #{type} for #{path}")
          end
        end
      end

      def search_manifest(manifest_path:, target_path_regex:)
        manifest = BackupEngine::Manifest.download(path: manifest_path, encryption_engine: @encryption_engine)
        @logger.debug('Manifest download complete')
        @logger.warn('Manifest is incomplete and will be missing files') if manifest.partial

        _targeted_manifest(manifest: manifest.manifest, target_path_regex: target_path_regex).each_pair do |path_obj, metadata|
          @logger.info("Found Match: #{path_obj} (#{metadata.type})")
        end
      end

      private

      def _set_attributes(path:, metadata:)
        # Order important: chown after chmod will reset sticky bits
        FileUtils.chown(metadata.stat.uid, metadata.stat.gid, path)
        FileUtils.chmod(metadata.stat.mode, path)
      end

      def _restore_file(path:, metadata:)
        # Create on the same filesystem as the target so the move is atomic
        Tempfile.create('restore_client', path.dirname.to_s) do |tmpfile|
          FileUtils.chmod(0o600, tmpfile.path)

          offset = tmpfile.tell
          metadata.block_map.each do |block_metadata|
            raise("Restore Error: #{path}: offset mismatch: #{offset}:#{block_metadata['offset']}") if offset != block_metadata['offset']

            tmpfile.write(BackupEngine::BlockEncoder.restore(path: Pathname.new(block_metadata['path']), encryption_engine: @encryption_engine).data)
            offset = tmpfile.tell
            @logger.debug("#{path}: Restored #{offset}/#{metadata['stat']['size']} bytes")
          end

          tmpfile.close

          raise("Restore Error: #{path}: Size mismatch: #{File.size(tmpfile.path)}:#{metadata.stat.size}") if File.size(tmpfile.path) != metadata.stat.size

          BackupEngine::Checksums::Engine.parse(metadata.checksum).verify_file(tmpfile.path)

          FileUtils.mv(tmpfile.path, path)
        rescue BackupEngine::Checksums::ChecksumMismatch => e
          raise("Restore Error: #{path}: Checksum mismatch: #{e}")
        end
        _set_attributes(path: path, metadata: metadata)
        @logger.info("#{path}: Restored")
      end

      def _restore_fifo(path:, metadata:)
        File.mkfifo(path)
        _set_attributes(path: path, metadata: metadata)
        @logger.info("#{path}: Restored")
      end

      def _restore_directory(path:, metadata:)
        FileUtils.mkdir(path)
        _set_attributes(path: path, metadata: metadata)
        @logger.info("#{path}: Restored")
      end

      def _restore_symlink(path:, metadata:)
        FileUtils.ln_s(metadata.target, path)
        @logger.info("#{path}: Restored")
      end

      def _targeted_manifest(manifest:, target_path_regex:)
        @logger.debug('Generating targeted manifest')
        targeted_manifest = {}
        manifest.each_pair do |path, metadata|
          unless path =~ /#{target_path_regex}/
            @logger.debug("Skipping #{path} per target_path_regex")
            next
          end

          path_obj = BackupEngine::Pathname.new(path)

          # Include parent directories in the restore to restore directory permissisons
          path_obj.fully_qualified_parent_directories.each do |parent_dir|
            next if parent_dir.to_s == '/'
            next if targeted_manifest.key?(parent_dir)

            unless manifest.key?(parent_dir.to_s)
              @logger.warn("Parent directory #{parent_dir} of target #{path} not in manifest")
              next
            end

            @logger.debug("Adding parent directory #{parent_dir} of target #{path} to the target manifest")
            targeted_manifest[parent_dir] = manifest[parent_dir.to_s]
          end

          targeted_manifest[path_obj] = metadata
        end

        return targeted_manifest
      end
    end
  end
end
