require 'logger'

require_relative '../lib/backup_client/upload_api.rb'
require_relative '../lib/backup_client/checksums.rb'
require_relative '../lib/backup_client/encryption.rb'
require_relative '../lib/backup_client/backup_client.rb'


communicator = BackupClient::UploadAPI::FilesystemCommunicator.new(base_path: '../test/dst')
checksum_engine = BackupClient::Checksums::Engine.new("sha256")
encryption_engine = BackupClient::Encryption::Engine.new("none")
logger = Logger.new(STDOUT)

engine = BackupClient::Backup::Engine.new(api_communicator: communicator,
                                          checksum_engine: checksum_engine,
                                          encryption_engine: encryption_engine,
                                          host: 'testhost',
                                          chunk_size: (1024 * 1024 * 25),
                                          logger: logger)
engine.backup_path(path: Pathname.new(File.expand_path('../test/src')))
