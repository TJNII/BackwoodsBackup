require_relative 'spec_helper.rb'

require_relative '../lib/backup_engine/communicator/filesystem.rb'
require_relative '../lib/backup_engine/checksums/engine.rb'
require_relative '../lib/backup_engine/encryption/engine.rb'
require_relative '../lib/backup_engine/client/engine.rb'

require 'logger'

# This is intended to be run in a Docker container.
describe 'Backup Engine: Functional' do
  target_paths = Pathname.new('/').children.reject { |path| %w[/proc /sys /dev /tmp].include? path.to_s }.freeze

  before :all do

    @communicator = BackupEngine::Communicator::Filesystem.new(base_path: '/tmp/test_backup_output')
    @checksum_engine = BackupEngine::Checksums::Engine.new("sha256")
    @encryption_engine = BackupEngine::Encryption::Engine.new("none")
    @logger = Logger.new(STDOUT)

    @engine = BackupEngine::Client::Engine.new(api_communicator: @communicator,
                                               checksum_engine: @checksum_engine,
                                               encryption_engine: @encryption_engine,
                                               host: 'testhost',
                                               chunk_size: (1024 * 1024 * 25),
                                               logger: @logger)
  end

  target_paths.each do |path|
    it "backs up #{path}" do
      @engine.backup_path(path: path)
    end
  end

  it "saves the manifest" do
    @engine.upload_manifest
  end

  pending "restores files"
end
    
  
