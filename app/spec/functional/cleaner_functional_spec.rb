require 'English'
require 'logger'

require 'fileutils'
require 'securerandom'

require_relative '../spec_helper.rb'

require_relative '../../lib/backup_engine/cleaner.rb'
require_relative '../../lib/backup_engine/communicator.rb'
require_relative '../../lib/backup_engine/encryption/engine.rb'

# This is intended to be run in a Docker container.
# Note that the cleaner is also called in the backup engine functional spec to ensure it doesn't remove things it shouldn't.
describe 'Cleaner: Functional' do
  let(:backup_directory) do
    # Not worrying about cleanup as this is intended to be run in a Docker container.
    tempdir = Pathname.new('/tmp/').join("cleaner_tests-#{SecureRandom.hex}")
    FileUtils.cp_r('/app/spec/fixtures/cleaner_fixtures/cleaner_backup', tempdir)
    tempdir
  end

  let(:logger) do
    logger = Logger.new(STDOUT)
    logger.level = Logger::INFO
    logger
  end

  let(:communicator) { BackupEngine::Communicator.new(type: 'filesystem', backend_config: { base_path: backup_directory }) }
  let(:encryption_keys) do
    {
      test_key_1: {
        private: File.read('/app/spec/fixtures/cleaner_fixtures/fixture_generation/config/test1.key.pem')
      },
      test_key_2: {
        private: File.read('/app/spec/fixtures/cleaner_fixtures/fixture_generation/config/test2.key.pem')
      }
    }
  end

  let(:encryption_engine) do
    BackupEngine::Encryption::Engines::ASymmetricRSA.new(communicator: communicator,
                                                         keys: encryption_keys,
                                                         logger: logger)
  end

  let(:blocks_path_obj) { Pathname.new(backup_directory).join('blocks') }
  let(:random_block_path_obj) { blocks_path_obj.children[rand(0..(blocks_path_obj.children.length - 1))] }
  let(:manifests_path_obj) { Pathname.new(backup_directory).join('manifests') }

  describe 'block cleaning' do
    describe 'asymmetric block consistency' do
      pending 'it warns if the manifest only keys can decrypt data blocks'

      it 'removes keys without a corresponding symmetric block' do
        raise("Fixture failure: #{random_block_path_obj} does not have two keys") unless random_block_path_obj.join('ASymmetricRSA').join('asym_keys').children.length == 2
        raise("Fixture failure: #{random_block_path_obj} does not have two blocks") unless random_block_path_obj.join('ASymmetricRSA').join('asym_blocks').children.length == 2

        sym_block_dir = random_block_path_obj.join('ASymmetricRSA').join('asym_blocks').children[0]
        raise("Fixture failure: #{sym_block_dir} is not a directory") unless sym_block_dir.directory?

        FileUtils.rm_r(sym_block_dir)
        BackupEngine::Cleaner.clean(encryption_engine: encryption_engine, logger: logger, min_block_age: 0, min_manifest_age: 3600, min_set_manifests: 128)
        expect(random_block_path_obj.join('ASymmetricRSA').join('asym_keys').directory?).to be true
        expect(random_block_path_obj.join('ASymmetricRSA').join('asym_keys').children.length).to eq 1
      end

      it 'removes symmetric blocks without a corresponding asymmetric key' do
        raise("Fixture failure: #{random_block_path_obj} does not have two keys") unless random_block_path_obj.join('ASymmetricRSA').join('asym_keys').children.length == 2
        raise("Fixture failure: #{random_block_path_obj} does not have two blocks") unless random_block_path_obj.join('ASymmetricRSA').join('asym_blocks').children.length == 2

        key_dir = random_block_path_obj.join('ASymmetricRSA').join('asym_keys').children[0]
        raise("Fixture failure: #{key_dir} is not a directory") unless key_dir.directory?

        FileUtils.rm_r(key_dir)
        BackupEngine::Cleaner.clean(encryption_engine: encryption_engine, logger: logger, min_block_age: 0, min_manifest_age: 3600, min_set_manifests: 128)
        expect(random_block_path_obj.join('ASymmetricRSA').join('asym_blocks').directory?).to be true
        expect(random_block_path_obj.join('ASymmetricRSA').join('asym_blocks').children.length).to eq 1
      end

      describe 'directory cleanup' do
        # This is mainly for the filesystem communicator, as S3 doesn't have true directories
        # However, it is still useful as it catches corner cases in the cleanup methods when the storage is in a unexpected state (files missing)

        target_block = Pathname.new('/app/spec/fixtures/cleaner_fixtures/cleaner_backup/blocks').children[0]
        `cd #{target_block}; find ./`.split.map { |p| Pathname.new(p) }.each do |path|
          next unless target_block.join(path).directory?

          it "removes empty directories: #{target_block.basename.join(path)}" do
            target_dir = backup_directory.join('blocks').join(target_block.basename).join(path)
            raise("Test Error: #{target_dir} is not a directory") unless target_dir.directory?

            target_dir.children.each do |child_path|
              FileUtils.rm_r(child_path)
            end

            BackupEngine::Cleaner.clean(encryption_engine: encryption_engine, logger: logger, min_block_age: 0, min_manifest_age: 3600, min_set_manifests: 128)
            expect(target_dir.directory?).to be false
          end
        end
      end
    end

    describe 'manifest cleaning' do
      it 'reports missing blocks' do
        FileUtils.rm_r(random_block_path_obj)
        expect(logger).to receive(:error).with(%r{Manifest manifests/tests/fixture_./[0-9]+ incomplete: Block blocks/#{random_block_path_obj.basename} missing!}).at_least(:once)
        BackupEngine::Cleaner.clean(encryption_engine: encryption_engine, logger: logger, min_block_age: 0, min_manifest_age: 3600, min_set_manifests: 128)
      end

      pending 'reports blocks undecryptable with keys used for backup'

      it 'removes unreferenced blocks' do
        unreferenced_block = blocks_path_obj.join('test_unreferenced')
        FileUtils.cp_r(random_block_path_obj, unreferenced_block)
        raise('Test error: unreferenced_block not a directory') unless unreferenced_block.directory?

        BackupEngine::Cleaner.clean(encryption_engine: encryption_engine, logger: logger, min_block_age: 0, min_manifest_age: 3600, min_set_manifests: 128)
        expect(unreferenced_block.directory?).to be false
      end

      it 'keeps unreferenced blocks newer than min_block_age' do
        unreferenced_block = blocks_path_obj.join('test_unreferenced')
        FileUtils.cp_r(random_block_path_obj, unreferenced_block)
        raise('Test error: unreferenced_block not a directory') unless unreferenced_block.directory?

        BackupEngine::Cleaner.clean(encryption_engine: encryption_engine, logger: logger, min_block_age: 3600, min_manifest_age: 3600, min_set_manifests: 128)
        expect(unreferenced_block.directory?).to be true
      end

      it 'removes old manifests' do
        raise('Test Error: No manifests') if manifests_path_obj.children.empty?

        BackupEngine::Cleaner.clean(encryption_engine: encryption_engine, logger: logger, min_block_age: 0, min_manifest_age: 0, min_set_manifests: 0)
        expect(manifests_path_obj.children.length).to eql 0
      end

      it 'saves the last min_set_manifests for each set' do
        manifests_path_obj.children.each do |host|
          host.children.each do |set|
            raise("Test Fixture Error: #{set} has less than the required number of fixture manifests") if set.children.length <= 2
          end
        end

        BackupEngine::Cleaner.clean(encryption_engine: encryption_engine, logger: logger, min_block_age: 0, min_manifest_age: 0, min_set_manifests: 2)
        manifests_path_obj.children.each do |host|
          host.children.each do |set|
            expect(set.children.length).to eq 2
          end
        end
      end

      describe 'directory cleanup' do
        fixture_manifests_dir = Pathname.new('/app/spec/fixtures/cleaner_fixtures/cleaner_backup/manifests').children[0]
        `cd #{fixture_manifests_dir}; find ./`.split.map { |p| Pathname.new(p) }.each do |path|
          next unless fixture_manifests_dir.join(path).directory?

          it "removes empty directories: #{fixture_manifests_dir.basename.join(path)}" do
            target_dir = manifests_path_obj.join(fixture_manifests_dir.basename).join(path)
            raise("Test Error: #{target_dir} is not a directory") unless target_dir.directory?

            target_dir.children.each do |child_path|
              FileUtils.rm_r(child_path)
            end

            BackupEngine::Cleaner.clean(encryption_engine: encryption_engine, logger: logger, min_block_age: 0, min_manifest_age: 3600, min_set_manifests: 128)
            expect(target_dir.directory?).to be false
          end
        end
      end
    end
  end
end
