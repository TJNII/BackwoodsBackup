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

        manifest['manifest'].each_pair do |path, metadata|
          unless path =~ /#{target_path_regex}/
            @logger.debug("Skipping #{path} per target_path_regex")
            next
          end

          path_obj = Pathname.new(path)
          path_obj = path_obj.relative_path_from(Pathname.new('/')) if path_obj.absolute?
          full_path = restore_path.join(path_obj)

          FileUtils.mkdir_p(full_path.dirname) unless full_path.dirname.directory?

          case metadata['type']
          when 'file'
            _restore_file(path: full_path, metadata: metadata)
          when 'directory'
            _restore_directory(path: full_path, metadata: metadata)
          when 'symlink'
            _restore_symlink(path: full_path, metadata: metadata)
          else
            raise("Unknown file type #{type} for #{path}")
          end
        end
      end

      private

      def _set_attributes(path:, metadata:)
        # Order important: chown after chmod will reset sticky bits
        FileUtils.chown(metadata['stat']['uid'], metadata['stat']['gid'], path)
        FileUtils.chmod(metadata['stat']['mode'], path)
      end

      def _restore_file(path:, metadata:)
        Tempfile.create('restore_client') do |tmpfile| # TODO: configurable path
          FileUtils.chmod(0o600, tmpfile.path)

          offset = tmpfile.tell
          metadata['block_map'].each do |block_metadata|
            raise("Restore Error: #{path}: offset mismatch: #{offset}:#{block_metadata['offset']}") if offset != block_metadata['offset']

            tmpfile.write(BackupEngine::BlockEncoder.restore(path: Pathname.new(block_metadata['path']), encryption_engine: @encryption_engine).data)
            offset = tmpfile.tell
            @logger.debug("#{path}: Restored #{offset}/#{metadata['stat']['size']} bytes")
          end

          tmpfile.close

          raise("Restore Error: #{path}: Size mismatch: #{File.size(tmpfile.path)}:#{metadata['stat']['size']}") if File.size(tmpfile.path) != metadata['stat']['size']

          BackupEngine::Checksums::Engine.parse(metadata['checksum']).verify_file(tmpfile.path)

          FileUtils.mv(tmpfile.path, path)
        rescue BackupEngine::Checksums::ChecksumMismatch => e
          raise("Restore Error: #{path}: Checksum mismatch: #{e}")
        end
        _set_attributes(path: path, metadata: metadata)
        @logger.info("#{path}: Restored")
      end

      def _restore_directory(path:, metadata:)
        FileUtils.mkdir(path)
        _set_attributes(path: path, metadata: metadata)
        @logger.info("#{path}: Restored")
      end

      def _restore_symlink(path:, metadata:)
        FileUtils.ln_s(metadata.fetch('target'), path)
        @logger.info("#{path}: Restored")
      end
    end
  end
end
