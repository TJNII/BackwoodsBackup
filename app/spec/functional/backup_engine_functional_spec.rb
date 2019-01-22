require 'English'
require 'logger'

require_relative '../spec_helper.rb'

require_relative '../../lib/backup_engine/backup_client/engine.rb'
require_relative '../../lib/backup_engine/checksums/engine.rb'
require_relative '../../lib/backup_engine/cleaner.rb'
require_relative '../../lib/backup_engine/communicator.rb'
require_relative '../../lib/backup_engine/compression/engine.rb'
require_relative '../../lib/backup_engine/docker_bind_pathname.rb'
require_relative '../../lib/backup_engine/encryption/engine.rb'
require_relative '../../lib/backup_engine/manifest.rb'
require_relative '../../lib/backup_engine/restore_client/engine.rb'

# This is intended to be run in a Docker container.
describe 'Backup Engine: Functional' do
  excluded_paths = %w[/proc /sys /dev /tmp /ramdisk].freeze
  target_paths = Pathname.new('/').children.sort.freeze

  before :all do
    @logger = Logger.new(STDOUT)
    @communicator = BackupEngine::Communicator.new(type: 'filesystem', backend_config: { base_path: '/tmp/test_backup_output' })

    @encryption_keys = {}.tap do |h|
      # TODO: Test with multiple keys
      1.times do |c|
        key = OpenSSL::PKey::RSA.new(2048)
        h["key#{c}"] = { public: key.public_key.to_s, private: key.to_s }
      end
    end

    @encryption_engine = BackupEngine::Encryption::Engines::ASymmetricRSA.new(communicator: @communicator,
                                                                              keys: @encryption_keys,
                                                                              logger: @logger)

    @checksum_engine = BackupEngine::Checksums::Engines::SHA256.new
    @compression_engine = BackupEngine::Compression::Engines::Zlib.new
    @manifest = BackupEngine::Manifest::Manifest.new(host: 'testhost', set_name: 'functional_test', logger: @logger)

    @backup_engine = BackupEngine::BackupClient::Engine.new(checksum_engine: @checksum_engine,
                                                            encryption_engine: @encryption_engine,
                                                            compression_engine: @compression_engine,
                                                            manifest: @manifest,
                                                            chunk_size: (512 * 1024), # Test with a small block size
                                                            logger: @logger,
                                                            path_exclusions: excluded_paths.map { |path| "^#{path}" },
                                                            tempdirs: { (1024**3) => '/ramdisk' })
  end

  target_paths.each do |path|
    it "backs up #{path}" do
      @backup_engine.backup_path(path: BackupEngine::DockerBindPathname.new(bind_path: nil, relative_path: path))
    end
  end

  it 'saves the manifest' do
    @manifest.upload(checksum_engine: @checksum_engine,
                     encryption_engine: @encryption_engine,
                     compression_engine: @compression_engine)
  end

  # This test is to ensure the cleaner doesn't remove things it shouldn't
  it 'cleans cleanly' do
    BackupEngine::Cleaner.clean(encryption_engine: @encryption_engine, logger: @logger, min_block_age: 0, min_manifest_age: 3600, min_set_manifests: 128)
  end

  it 'restores without errors' do
    restore_engine = BackupEngine::RestoreClient::Engine.new(encryption_engine: @encryption_engine, logger: @logger)
    restore_engine.restore_manifest(manifest_path: @backup_engine.manifest.path,
                                    restore_path: BackupEngine::Pathname.new('/tmp/test_restore'),
                                    target_path_regex: '.*')
  end

  target_paths.each do |path|
    if excluded_paths.include?(path.to_s)
      it "does not restore excluded path #{path}" do
        expect(File.exist?("/tmp/test_restore/#{path}")).to be false
      end
      next
    end

    # Intentionally not using Ruby File methods in order to test differently than the implementation,
    describe "#{path} permissions" do
      perm_files_fd = Tempfile.new
      # Write the find directly into the subshell file to avoid problems with Ruby encoding
      `find #{path} | sed -e 's|^/||' > #{perm_files_fd.path}`
      raise('Failed to find files for permissions test') if $CHILD_STATUS != 0

      perm_files = File.read(perm_files_fd).force_encoding('ASCII-8BIT').split("\n")
      perm_files_fd.close

      before :all do
        # Stat all the files in one shell to avoid the cost of a subshell for each file
        @perm_output = Hash.new { |h, k| h[k] = Hash.new }.tap do |hash|
          { src: '/', dst: '/tmp/test_restore' }.each_pair do |key, tgt_path|
            raw = `cd #{tgt_path}; set -e; cat #{perm_files_fd.path} | while read file; do ls -nd --time-style=+ "${file}"; done`.force_encoding('ASCII-8BIT')
            raise("Failed to gather #{key} stats in #{tgt_path}") if $CHILD_STATUS != 0

            raw.split("\n").each do |line|
              split_line = line.split
              path = /(.*?)( ->.*)?$/.match(split_line[5..-1].join(' '))[1]

              hash[path][key] = split_line.reject.with_index { |_, i| [1, 4].include? i }
            end
          end
        end
      end

      perm_files.sort.each do |file|
        it "are correct for #{file}" do
          expect(@perm_output.fetch(file).fetch(:src).length).to be >= 3
          expect(@perm_output.fetch(file).fetch(:dst).length).to be >= 3
          expect(@perm_output.fetch(file).fetch(:dst)).to eql(@perm_output.fetch(file).fetch(:src))
        end
      end
    end

    describe "#{path} contents" do
      cont_files_fd = Tempfile.new
      # Write the find directly into the subshell file to avoid problems with Ruby encoding
      # Note different find: -f flag
      `find #{path} -type f | sed -e 's|^/||' > #{cont_files_fd.path}`
      raise('Failed to find files for contents test') if $CHILD_STATUS != 0

      cont_files = File.read(cont_files_fd).force_encoding('ASCII-8BIT').split("\n")
      cont_files_fd.close

      before :all do
        @cont_output = Hash.new { |h, k| h[k] = Hash.new }.tap do |hash|
          { src: '/', dst: '/tmp/test_restore' }.each_pair do |key, tgt_path|
            raw = `cd #{tgt_path}; set -e; cat #{cont_files_fd.path} | while read file; do echo "${file}_:_$(cat "${file}" | wc -c)_:_$(sha512sum "${file}")"; done`.force_encoding('ASCII-8BIT')
            raise("Failed to check #{key} contents #{tgt_path}") if $CHILD_STATUS != 0

            raw.split("\n").map { |line| line.split('_:_') }.each do |line|
              raise("Delimiter collision in '#{line}'") if line.length > 3

              hash[line.delete_at(0)][key] = line
            end
          end
        end
      end

      cont_files.sort.each do |file|
        it "are the same for #{file}" do
          expect(@cont_output.fetch(file).fetch(:src).length).to eq 2
          expect(@cont_output.fetch(file).fetch(:dst).length).to eq 2
          expect(@cont_output.fetch(file).fetch(:dst)).to eql(@cont_output.fetch(file).fetch(:src))
        end
      end
    end
  end
end
