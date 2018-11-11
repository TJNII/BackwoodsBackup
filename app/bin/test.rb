require 'logger'

require_relative '../lib/backup_engine/communicator/filesystem.rb'
require_relative '../lib/backup_engine/checksums/engine.rb'
require_relative '../lib/backup_engine/encryption/engine.rb'
require_relative '../lib/backup_engine/client/engine.rb'

communicator = BackupEngine::Communicator::Filesystem.new(base_path: '../test/dst')
checksum_engine = BackupEngine::Checksums::Engine.new("sha256")
encryption_engine = BackupEngine::Encryption::Engine.new("none")
logger = Logger.new(STDOUT)

engine = BackupEngine::Client::Engine.new(api_communicator: communicator,
                                          checksum_engine: checksum_engine,
                                          encryption_engine: encryption_engine,
                                          host: 'testhost',
                                          chunk_size: (1024 * 1024 * 25),
                                          logger: logger)
engine.backup_path(path: Pathname.new(File.expand_path('../test/src')))
