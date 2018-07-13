module BackupClient
  class APICommunicator
    def initialize(base_uri, backup_host)
      raise("STUBBED")
    end

#    def lookup_file_id(path:, checksum:, stat:)
#      raise("STUBBED")
#      # Needs to return ID
#    end

#    def file_backup_complete?(file_id:)
#      raise("STUBBED")
#      # Needs to return boolean
#    end

    def create_file_backup_entry(path:, checksum:, stat:)
      raise("STUBBED")
      # Needs to return ID
    end
      
    def delete_file_backup(file_id:)
      raise("STUBBED")
      # Raise on error
    end
    
    def lookup_block_id(unencrypted_checksum:, unencrypted_length:)
      raise("STUBBED")
      # Needs to return ID
    end

    def back_up_block(encrypted_data:, encrypted_checksum:, unencrypted_checksum:, unencrypted_length:)
      raise("STUBBED")
      # Needs to return ID
    end
    
    def create_block_map_entry(file_id:, block_id:, offset:)
      raise("STUBBED")
      # Needs to return ID
    end

#    def lookup_directory_id(path:, checksum:, stat:)
#      raise("STUBBED")
#      # Needs to return ID
#    end

    def create_directory_backup_entry(path:, checksum:, stat:)
      raise("STUBBED")
      # Needs to return ID
    end

#    def lookup_symlink_id(path:, checksum:, stat:, target:)
#      raise("STUBBED")
#      # Needs to return ID
#    end

    def create_symlink_backup_entry(path:, checksum:, stat:, target:)
      raise("STUBBED")
      # Needs to return ID
    end
  end
end
