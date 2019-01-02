require 'tempfile'
require 'fileutils'

require_relative '../stat.rb'
require_relative '../manifest.rb'
require_relative '../block_encoder.rb'

module BackupEngine
  module BackupClient
    class UnsupportedFileType < StandardError
    end

    class Engine
      attr_reader :checksum_engine, :communicator, :manifest, :encryption_engine, :compression_engine, :chunk_size

      def initialize(checksum_engine:, encryption_engine:, compression_engine:, host:, chunk_size:, logger:, path_exclusions: [], tempdirs: {})
        @checksum_engine = checksum_engine
        @manifest = BackupEngine::Manifest::Manifest.new(backup_host: host)
        @encryption_engine = encryption_engine
        @compression_engine = compression_engine
        @chunk_size = chunk_size
        @logger = logger
        @path_exclusions = path_exclusions.freeze
        @tempdirs = tempdirs.freeze
      end

      def backup_path(path:)
        if _path_excluded?(path)
          @logger.info("Skipping #{path} per exclusion list")
          return
        end

        # File.stat follows symlinks.
        if File.symlink? path.absolute_path
          _backup_symlink(path: path)
          return
        end

        stat = BackupEngine::Stat.file_stat(path.absolute_path)

        case stat.file_type
        when :file
          _backup_file(path: path, stat: stat)
        when :fifo
          _backup_fifo(path: path, stat: stat)
        when :directory
          _backup_directory(path: path, stat: stat)
        else
          raise(BackupEngine::BackupClient::UnsupportedFileType, "#{path}: Unsupported file type #{stat.file_type}")
        end

        if stat.file_type == :directory
          path.children.sort.each do |sub_path|
            backup_path(path: sub_path)
          end
        end
      rescue StandardError => exc
        # TODO: This fails the whole parent path
        @logger.error("Exception backing up #{path}: #{exc}")
        raise exc
      end

      def upload_manifest(partial: false)
        @manifest.partial = true if partial
        @manifest.upload(checksum_engine: @checksum_engine,
                         encryption_engine: @encryption_engine,
                         compression_engine: @compression_engine)

        if partial
          @logger.warn("Uploaded incomplete manifest to #{@manifest.path}")
        else
          @logger.info("Uploaded manifest to #{@manifest.path}")
        end
      end

      private

      def _backup_file(path:, stat:)
        checksum = @checksum_engine.file(path.absolute_path)

        # Copy the target to a tmpfile in case it changes while backing up
        _create_tempfile(path: path, stat: stat) do |tmpfile|
          FileUtils.chmod(0o600, tmpfile.path)
          FileUtils.cp(path.absolute_path, tmpfile.path)
          if @checksum_engine.file(tmpfile.path) != checksum
            @logger.error("#{path} changed while being backed up")
            return
          end

          raise('INTERNAL ERROR: tmpfile pointer not at 0') unless tmpfile.tell == 0

          block_map = []
          until tmpfile.eof?
            offset = tmpfile.tell
            block = BackupEngine::BlockEncoder::Block.new(data: tmpfile.read(@chunk_size),
                                                          checksum_engine: @checksum_engine,
                                                          encryption_engine: @encryption_engine)

            raise("INTERNAL ERROR: Short Read: #{block.length}/#{@chunk_size}") if block.length != @chunk_size && !tmpfile.eof?

            if block.backed_up?
              @logger.debug("#{path} @#{offset}: Backed up #{block.length}/#{stat.size} bytes using existing block")
            else
              result = block.back_up(compression_engine: @compression_engine)
              @logger.debug("#{path} @#{offset}: Backed up #{block.length}/#{stat.size} bytes as new block.  Compressed #{result[:compression_percent]}%")
            end

            block_map.push(offset: offset, path: block.path)
          end

          @manifest.create_file_backup_entry(path: path,
                                             checksum: checksum,
                                             stat: stat,
                                             block_map: block_map)
        end

        @logger.info("#{path}: backed up")
      end

      def _backup_directory(path:, stat:)
        @manifest.create_directory_backup_entry(path: path, stat: stat)
        @logger.info("#{path}: backed up")
      end

      def _backup_fifo(path:, stat:)
        @manifest.create_fifo_backup_entry(path: path, stat: stat)
        @logger.info("#{path}: backed up")
      end

      def _backup_symlink(path:)
        target = File.readlink(path.absolute_path)
        @manifest.create_symlink_backup_entry(path: path, target: target)
        @logger.info("#{path}: backed up")
      end

      def _create_tempfile(path:, stat:)
        # @tempdirs is a hash of { [max size in bytes] => [path] } pairs
        # This allows for multiple tiers of temp space
        # For example: small files in ram, medium files on SSD, large files on spinning rust
        # If the file size exceedes all max sizes a nil tempdir is passed to Tempfile.create, which then uses the default
        tempdir = @tempdirs.select { |k| k > stat.size }.values[0]
        if tempdir.nil?
          # This is a warning as the Tempfile default is inside the container, which is likely a slow copy-on-write filesystem
          @logger.warn("#{path} (#{stat.size} bytes) is larger than all configured temp dirs, using Tempfile default")
        else
          @logger.debug("#{path}: #{stat.size} bytes: using #{tempdir} temp space")
        end

        Tempfile.create('backup_client', tempdir) do |tmpfile|
          yield(tmpfile)
        end
      end

      def _path_excluded?(path)
        @path_exclusions.each do |exclusion|
          # The encode resolves issues with non-ASCII filenames.
          # It's a little fast and loose, but as this is a exclusion matcher it should fail-safe.
          return true if path.to_s.encode!('UTF-8', invalid: :replace, replace: '.') =~ /#{exclusion}/
        end
        return false
      end
    end
  end
end
