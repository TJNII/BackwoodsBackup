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

  before :all do
    @communicator = BackupEngine::Communicator.new(type: "filesystem", backend_config: {base_path: '/tmp/test_backup_output'})
    @checksum_engine = BackupEngine::Checksums::Engines::SHA256.new
    @encryption_engine = BackupEngine::Encryption::Engines::None.new(communicator: @communicator)
    @compression_engine = BackupEngine::Compression::Engines::Zlib.new
    @logger = Logger.new(STDOUT)

    @backup_engine = BackupEngine::BackupClient::Engine.new(checksum_engine: @checksum_engine,
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
    restore_engine = BackupEngine::RestoreClient::Engine.new(encryption_engine: @encryption_engine, logger: @logger)
    restore_engine.restore_manifest(manifest_path: @backup_engine.manifest.path,
                                    restore_path: Pathname.new('/tmp/test_restore'))
  end

  target_paths.each do |path|
    # Intentionally not using Ruby File methods in order to test differently than the implementation,

    describe "#{path} permissions" do
      files = `find #{path}`.split("\n").map { |file| file.sub(%r{^/}, '') }
      before :all do
        # Stat all the files in one shell to avoid the cost of a subshell for each file
        files_fd = Tempfile.new
        files_fd.write(files.join("\n"))
        files_fd.close

        @perm_output = Hash.new { |h,k| h[k] = Hash.new }.tap do |hash|
          {src: '/tmp/test_restore', dst: '/'}.each_pair do |key, tgt_path|
            raw = `cd #{tgt_path}; set -e; cat #{files_fd.path} | while read file; do ls -nd --time-style=+ "${file}"; done`
            raise("Failed to gather #{key} stats in #{tgt_path}") if $? != 0
            raw.split("\n").each do |line|
              parsed_line = line.split.select.with_index { |_, i| [0, 2, 3, 5].include? i }
              hash[parsed_line.delete_at(3)][key] = parsed_line
            end
          end
        end
      end
              
      files.each do |file|
        it "are correct for #{file}" do
          expect(@perm_output[file][:dst]).to eql(@perm_output[file][:src])
        end
      end

      describe "#{path} contents" do
        files = `find #{path} -type f`.split("\n").map { |file| file.sub(%r{^/}, '') }
        before :all do
          # Stat all the files in one shell to avoid the cost of a subshell for each file
          files_fd = Tempfile.new
          files_fd.write(files.join("\n"))
          files_fd.close

          @cont_output = Hash.new { |h,k| h[k] = Hash.new }.tap do |hash|
            {src: '/tmp/test_restore', dst: '/'}.each_pair do |key, tgt_path|
              raw = `cd #{tgt_path}; set -e; cat #{files_fd.path} | while read file; do echo "$(ls "${file}" -d):$(cat "${file}" | wc -c):$(sha512sum "${file}")"; done`
              raise("Failed to check #{key} contents #{tgt_path}") if $? != 0
              raw.split("\n").map { |line| line.split(':') }.each do |line|
                hash[line.delete_at(0)][key] = line
              end
            end
          end
        end

        files.each do |file|
          it "are the same for #{file}" do
            expect(@cont_output[file][:dst]).to eql(@cont_output[file][:src])
          end
        end
      end
    end
  end
end
