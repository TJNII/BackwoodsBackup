require 'tempfile'
require 'fileutils'

require_relative '../stat.rb'
require_relative 'manifest.rb'
require_relative 'block.rb'

module BackupEngine
  module BackupClient
    class UnsupportedFileType < StandardError
    end

    class Engine
      attr_reader :checksum_engine, :communicator, :metadata_encoder, :encryption_engine, :compression_engine, :chunk_size

      def initialize(communicator:, checksum_engine:, encryption_engine:, compression_engine:, host:, chunk_size:, logger:)
        @checksum_engine = checksum_engine
        @communicator = communicator
        @manifest = Manifest.new(backup_host: host)
        @encryption_engine = encryption_engine
        @compression_engine = compression_engine
        @chunk_size = chunk_size
        @logger = logger
      end

      def backup_path(path:)
        # File.stat follows symlinks.
        if File.symlink? path
          _backup_symlink(path: path)
          return
        end

        stat = BackupEngine::Stat.file_stat(path)
        
        case stat.file_type
        when :file
          _backup_file(path: path, stat: stat)
        when :directory
          _backup_directory(path: path, stat: stat)
        else
          raise(BackupEngine::BackupClient::UnsupportedFileType, "#{path}: Unsupported file type #{stat.file_type}")
        end

        if stat.file_type == :directory
          path.children.each do |sub_path|
            backup_path(path: sub_path)
          end
        end
#      rescue => exc
#        @logger.error("Exception backing up #{path}: #{exc}")
#        raise exc
      end

      def upload_manifest
        @manifest.upload(communicator: @communicator,
                         checksum_engine: @checksum_engine, 
                         encryption_engine: @encryption_engine,
                         compression_engine: @compression_engine)
      end

      private
      
      def _backup_file(path:, stat:)
        checksum = @checksum_engine.file(path)

        # Copy the target to a tmpfile in case it changes while backing up
        Tempfile.create('backup_client') do |tmpfile| # TODO: configurable path
          FileUtils.chmod(0600, tmpfile.path)
          FileUtils.cp(path, tmpfile.path)
          if @checksum_engine.file(tmpfile.path) != checksum
            @logger.error("#{path} changed while being backed up")
            return
          end

          raise("INTERNAL ERROR: tmpfile pointer not at 0") unless tmpfile.tell == 0

          block_map = []
          until tmpfile.eof?
            offset = tmpfile.tell
            block = Block.new(data: tmpfile.read(@chunk_size),
                              communicator: @communicator,
                              checksum_engine: @checksum_engine,
                              encryption_engine: @encryption_engine,
                              compression_engine: @compression_engine)
            if block.length != @chunk_size && !tmpfile.eof?
              raise("INTERNAL ERROR: Short Read: #{block.length}/#{@chunk_size}")
            end

            if block.backed_up?
              @logger.debug("#{path} @#{offset}: Backed up #{block.length}/#{stat.size} bytes using existing block")
            else 
              block.back_up
              @logger.debug("#{path} @#{offset}: Backed up #{block.length}/#{stat.size} bytes as new block.")
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

      def _backup_symlink(path:)
        target = File.readlink(path)
        @manifest.create_symlink_backup_entry(path: path, target: target)
        @logger.info("#{path}: backed up")
      end
    end
  end
end
