require_relative 'checksums.rb'

module BackupClient
  module Backup
    class UnsupportedFileType < StandardError
    end

    class BackupFailure < StandardError
    end

    class FileChangedDuringBackup < BackupFailure
    end

    class BackupBlock
      attr_reader :checksum, :id

      def initialize(data, api_communicator, checksum_engine, encryption_engine)
        @data = data.freeze

        @checksum_engine = checksum_engine
        @api_communicator = api_communicator
        @encryption_engine = encryption_engine

        @checksum = @checksum_engine.block(@data)
      end

      def backed_up?
        @id = api_communicator.lookup_block_id(unencrypted_checksum: @checksum,
                                               unencrypted_length: @data.length)
        return !block_id.nil?
      end

      def back_up
        encrypted_data = encryption_engine.encrypt(@data)
        encrypted_checksum = @checksum_engine.block(@encrypted_data)

        @id = api_communicator.back_up_block(encrypted_data: encrypted_data,
                                             encrypted_checksum: encrypted_checksum,
                                             unencrypted_checksum: @checksum,
                                             unencrypted_length: @data.length)
      end
    end

    class BackupEngine
      def initialize(api_communicator, checksum_engine, encryption_engine, config, logger)
        @checksum_engine = checksum_engine
        @api_communicator = api_communicator
        @encryption_engine = encryption_engine
        @config = config
        @logger = logger
      end

      def backup_path(path)
        stat = Stat.file_stat(path)
        
        



        tgt = if File.file?(path)
                BackupFile.new(path, api_communicator, checksum_engine, encryption_engine)
              elsif File.directory?(path)
                BackupDirectory.new(path, api_communicator)
              elsif File.symlink?(path)
                BackupSymlink.new(path)
              else
                raise(UnsupportedFileType("#{path}: Unsupported file type"))
              end

        if tgt.backed_up?
          @logger.info("#{path}: up to date")
        else
          tgt.back_up
          @logger.info("#{path}: backed up")
        end

        if File.directory?(path)
          Dir.entries(path).each do |sub_path|
            backup_path(sub_path, checksum_engine, api_communicator, encryption_engine)
          end
        end
      end

      private
      
      def _backup_file(path, stat)
        checksum = @checksum_engine.file(path)
        file_id = @api_communicator.create_file_backup_entry(path: path, checksum: checksum, stat: stat)

        open(path, "rb") do |fd|
          until fd.eof?
            offset = fd.tell
            block = BackupBlock.new(fd.read(chunk_size), @api_communicator, @checksum_engine, @encryption_engine)
            block.back_up unless block.backed_up?
            
            @api_communicator.create_block_map_entry(file_id: file_id,
                                                     block_id: block.id,
                                                     offset: offset)
            @logger.debug("#{path}: Backed up #{chunk_size}/#{stat.size} bytes from offset #{offset}")
          end
        end

        if @checksum_engine.file(path) != checksum
          @api_communicator.delete_file_backup(file_id: file_id)
          raise(FileChangedDuringBackup("#{@path} changed while being backed up"))
        end
      end
    
      def _backup_directory(path, stat)
        @api_communicator.create_directory_backup_entry(path: path, stat: stat)
      end

      def _backup_symlink(path, stat)
        target = File.readlink(@path)
        @api_communicator.create_symlink_backup_entry(path: path, stat: stat, target: target)
      end
    end
  end
end
