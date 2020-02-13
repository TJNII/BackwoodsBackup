require 'fileutils'
require 'securerandom'
require_relative '../../spec_helper.rb'
require_relative '../../helpers/s3_mocks.rb'

require_relative '../../../lib/backup_engine/communicator.rb'

describe 'Backup Engine: unit' do
  describe BackupEngine::Communicator do
    shared_examples 'common behavior' do
      describe '.date' do
        it 'returns the date of the object' do
          test_path = 'foo'
          test_obj.upload(path: test_path, metadata: '', payload: '')
          expect(test_obj.date(path: test_path)).to be_instance_of(Time)
          expect(test_obj.date(path: test_path).to_f).to be_within(0.1).of(Time.now.to_f)
        end
      end

      describe '.delete' do
        before :each do
          ['foo/bar/foobar',
           'foo/bar/foobaz',
           'foo/baz/foobar',
           'foo/baz/foobaz'].each do |test_path|
            test_obj.upload(path: test_path, metadata: '', payload: '')
          end
        end

        it 'deletes paths and subpaths' do
          test_obj.delete(path: 'foo/bar')
          ['foo/bar', 'foo/bar/foobar', 'foo/bar/foobaz'].each do |test_path|
            expect(test_obj.exists?(path: test_path)).to eq false
          end

          ['foo/baz', 'foo/baz/foobar', 'foo/baz/foobaz'].each do |test_path|
            expect(test_obj.exists?(path: test_path)).to eq true
          end
        end

        it 'Does nothing if the path does not exist' do
          test_obj.delete(path: 'bogus/path')
          ['foo/bar/foobar', 'foo/bar/foobaz', 'foo/baz/foobar', 'foo/baz/foobaz'].each do |test_path|
            expect(test_obj.exists?(path: test_path)).to eq true
          end
        end
      end

      describe '.download' do
        it 'returns the payload and metadata fo an object' do
          test_path = 'foo'
          test_metadata = SecureRandom.hex
          test_payload = SecureRandom.hex

          test_obj.upload(path: test_path, metadata: test_metadata, payload: test_payload)
          response = test_obj.download(path: test_path)
          expect(response[:metadata]).to eq(test_metadata)
          expect(response[:payload]).to eq(test_payload)
        end

        pending 'it raises on bad checksums when checksum verification is enabled'
      end

      describe '.exists?' do
        it 'returns true if the object exists' do
          test_path = 'foo/bar/baz'
          test_obj.upload(path: test_path, metadata: '', payload: '')
          expect(test_obj.exists?(path: test_path)).to eq true
        end

        it 'returns false if the object does not exist' do
          test_path = 'foo/bar/baz'
          expect(test_obj.exists?(path: test_path)).to eq false
        end
      end

      describe '.list' do
        before :each do
          ['foo/bar/foobar',
           'foo/bar/foobaz'].each do |test_path|
            test_obj.upload(path: test_path, metadata: '', payload: '')
          end
        end

        it 'returns the objects for the path' do
          expect(test_obj.list(path: BackupEngine::Pathname.new('foo'))).to eq(['foo/bar'].map { |p| BackupEngine::Pathname.new(p) })
          expect(test_obj.list(path: BackupEngine::Pathname.new('foo/bar'))).to eq(['foo/bar/foobar', 'foo/bar/foobaz'].map { |p| BackupEngine::Pathname.new(p) })
        end

        it 'supports depth' do
          expect(test_obj.list(path: BackupEngine::Pathname.new('foo'), depth: 2)).to eq(['foo/bar/foobar', 'foo/bar/foobaz'].map { |p| BackupEngine::Pathname.new(p) })
        end
      end

      # .upload is implicitly checked as it is used to set the initial state for all the other checks
    end

    describe 'Filesystem Communicator' do
      let(:logger) { Logger.new('/dev/null') }

      let(:test_filesystem_base_path) do
        path = Pathname.new('/tmp').join(SecureRandom.hex)
        FileUtils.mkdir_p(path)
        path
      end

      let(:test_obj) { described_class.new(type: 'filesystem', logger: logger, backend_config: { base_path: test_filesystem_base_path }) }

      after :each do
        FileUtils.rm_rf(test_filesystem_base_path)
      end

      it_behaves_like 'common behavior'
    end

    describe 'S3 Communicator' do
      let(:logger) { Logger.new('/dev/null') }
      let(:bucket) { SecureRandom.hex }
      let(:s3_client_config) { { stub_responses: true } }

      let(:mock_s3) { BackupEngineTestHelpers::S3Mocks.new }
      let(:test_obj) do
        described_class.new(type: 's3',
                            logger: logger,
                            backend_config: {
                              bucket: bucket,
                              s3_client_config: s3_client_config
                            }).tap do |tapped_test_obj|
          mock_s3.stub_client(aws_s3_sdk_client: tapped_test_obj.instance_variable_get(:@backend).instance_variable_get(:@s3))
        end
      end

      it_behaves_like 'common behavior'
    end
  end
end
