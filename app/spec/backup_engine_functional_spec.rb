require_relative 'spec_helper.rb'

require_relative '../lib/backup_engine/communicator.rb'
require_relative '../lib/backup_engine/checksums/engine.rb'
require_relative '../lib/backup_engine/encryption/engine.rb'
require_relative '../lib/backup_engine/compression/engine.rb'
require_relative '../lib/backup_engine/backup_client/engine.rb'
require_relative '../lib/backup_engine/restore_client/engine.rb'

require 'logger'

# This is intended to be run in a Docker container.
describe 'Backup Engine: Functional' do
  target_paths = Pathname.new('/').children.reject { |path| %w[/proc /sys /dev /tmp].include? path.to_s }.freeze

  let(:restore_path) {  Pathname.new('/tmp/test_restore') }

  before :all do
    @communicator = BackupEngine::Communicator.new(type: "filesystem", backend_config: {base_path: '/tmp/test_backup_output'})
    @checksum_engine = BackupEngine::Checksums::Engine.new("sha256")
    @encryption_engine = BackupEngine::Encryption::Engine.new("none")
    @compression_engine = BackupEngine::Compression::Engine.new("zlib")
    @logger = Logger.new(STDOUT)

    @backup_engine = BackupEngine::BackupClient::Engine.new(communicator: @communicator,
                                                            checksum_engine: @checksum_engine,
                                                            encryption_engine: @encryption_engine,
                                                            compression_engine: @compression_engine,
                                                            host: 'testhost',
                                                            chunk_size: (512 * 1024), # Test with a small block size
                                                            logger: @logger)
  end

  target_paths.each do |path|
    it "backs up #{path}" do
      @backup_engine.backup_path(path: path)
    end
  end

  it "saves the manifest" do
    @backup_engine.upload_manifest
  end

  it 'restores without errors' do
    restore_engine = BackupEngine::RestoreClient::Engine.new(communicator: @communicator, logger: @logger)
    restore_engine.restore_manifest(manifest_path: @backup_engine.manifest.path,
                                    restore_path: restore_path)
  end

  target_paths.each do |path|
    # Intentionally not using Ruby File methods in order to test differently than the implementation,
    # and because of odd behavior like File.stat() always following symlinks.
    files = `find #{path}`.split.map { |file| file.sub(%r{^/}, '') }
    files.each do |file|
      it "restores proper types and permissions on #{file}" do
        output = [restore_path, '/'].map do |tgt_path|
          # Ignore times, link count, sizes (Mismatch on directories)
          `cd #{tgt_path}; ls -nd --time-style=+ "#{file}"`.split.select.with_index { |_, i| [0, 2, 3].include? i }
        end
        expect(output[0]).to eql(output[1])
      end
    end

    files = `find #{path} -type f`.split.map { |file| file.sub(%r{^/}, '') }
    files.each do |file|
      it "restores proper file contents on #{file}" do
        output = [restore_path, '/'].map do |tgt_path|
          `cd #{tgt_path}; cat "#{file}" | wc -c; sha512sum "#{file}"`
        end
        expect(output[0]).to eql(output[1])
      end
    end
  end
end
