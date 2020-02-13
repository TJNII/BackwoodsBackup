require 'securerandom'
require_relative '../../../spec_helper.rb'
require_relative '../../../helpers/s3_mocks.rb'

require_relative '../../../../lib/backup_engine/communicator_backend/s3.rb'

describe 'Backup Engine: unit' do
  describe BackupEngine::CommunicatorBackend::S3 do
    let(:logger) { Logger.new('/dev/null') }
    let(:bucket) { SecureRandom.hex }
    let(:s3_client_config) { { stub_responses: true } }
    let(:cache_config) { {} }
    let(:storage_class) { 'STANDARD_IA' }
    let(:full_cache_seed) { true }

    let(:mock_s3) { BackupEngineTestHelpers::S3Mocks.new }
    let(:test_obj) do
      described_class.new(logger: logger,
                          bucket: bucket,
                          s3_client_config: s3_client_config,
                          cache_config: cache_config,
                          storage_class: storage_class,
                          full_cache_seed: full_cache_seed).tap do |tapped_test_obj|
        mock_s3.stub_client(aws_s3_sdk_client: tapped_test_obj.instance_variable_get(:@s3))
      end
    end

    describe '.date' do
      it 'returns the date of the object' do
        test_path = 'foo/bar/baz'
        test_date = Time.at(rand(0..1500000000))
        mock_s3.seed_object(bucket: bucket, key: test_path, body: '', last_modified: test_date, storage_class: storage_class)

        expect(test_obj.date(path: test_path)).to eq(test_date)
      end

      it 'uses cached dates' do
        test_path = 'foo/bar/baz'
        test_date = Time.at(rand(0..1500000000))

        # Cache must have something in it otherwise it will try and seed each call
        mock_s3.seed_object(bucket: bucket, key: '/unrelated/key', body: '', last_modified: Time.now, storage_class: storage_class)

        expect { test_obj.date(path: test_path) }.to raise_exception(Errno::ENOENT)
        mock_s3.seed_object(bucket: bucket, key: test_path, body: '', last_modified: test_date, storage_class: storage_class)
        expect { test_obj.date(path: test_path) }.to raise_exception(Errno::ENOENT)
      end
    end

    describe '.delete' do
      before :each do
        ['foo/bar/foobar',
         'foo/bar/foobaz',
         'foo/baz/foobar',
         'foo/baz/foobaz'].each do |test_path|
          mock_s3.seed_object(bucket: bucket, key: test_path, body: '', last_modified: Time.now, storage_class: storage_class)
        end

        test_obj.exists?(path: 'foo/bar') # Seed cache
      end

      it 'deletes paths and subpaths' do
        test_obj.delete(path: 'foo/bar')
        expect(mock_s3.object_paths(bucket: bucket)).to eq(['foo/baz/foobar', 'foo/baz/foobaz'])
      end

      it 'keeps the cache in sync' do
        test_obj.delete(path: 'foo/bar')
        ['foo/bar/foobar',
         'foo/bar/foobaz'].each do |test_path|
          expect(test_obj.exists?(path: test_path)).to eq false
        end

        ['foo/baz/foobar',
         'foo/baz/foobaz'].each do |test_path|
          expect(test_obj.exists?(path: test_path)).to eq true
        end
      end

      it 'fails of the cache is out of sync' do
        ['foo/bar/foobar',
         'foo/bar/foobaz'].each do |test_path|
          mock_s3.delete_object(bucket: bucket, key: test_path)
        end

        expect { test_obj.delete(path: 'foo/bar') }.to raise_exception(BackupEngine::CommunicatorBackend::S3CommunicatorError)
      end

      it 'Does nothing if the path does not exist' do
        test_obj.delete(path: 'bogus/path')
        expect(mock_s3.object_paths(bucket: bucket)).to eq(['foo/bar/foobar', 'foo/bar/foobaz', 'foo/baz/foobar', 'foo/baz/foobaz'])
      end
    end

    describe '.download' do
      it 'returns the contents of an object' do
        test_path = 'foo/bar/baz'
        test_body = SecureRandom.hex
        mock_s3.seed_object(bucket: bucket, key: test_path, body: test_body, last_modified: Time.now, storage_class: storage_class)

        expect(test_obj.download(path: test_path)).to eq(test_body)
      end
    end

    describe '.exists?' do
      it 'returns true if the object exists' do
        test_path = 'foo/bar/baz'
        mock_s3.seed_object(bucket: bucket, key: test_path, body: '', last_modified: Time.now, storage_class: storage_class)

        expect(test_obj.exists?(path: test_path)).to eq true
      end

      it 'returns false if the object does not exist' do
        test_path = 'foo/bar/baz'
        expect(test_obj.exists?(path: test_path)).to eq false
      end

      it 'uses the cache' do
        test_path = 'foo/bar/baz'

        # Cache must have something in it otherwise it will try and seed each call
        mock_s3.seed_object(bucket: bucket, key: '/unrelated/key', body: '', last_modified: Time.now, storage_class: storage_class)

        expect(test_obj.exists?(path: test_path)).to eq false
        mock_s3.seed_object(bucket: bucket, key: test_path, body: '', last_modified: Time.now, storage_class: storage_class)
        expect(test_obj.exists?(path: test_path)).to eq false
      end
    end

    describe '.list' do
      before :each do
        ['foo/bar/foobar',
         'foo/bar/foobaz'].each do |test_path|
          mock_s3.seed_object(bucket: bucket, key: test_path, body: '', last_modified: Time.now, storage_class: storage_class)
        end
      end

      it 'returns the objects for the path' do
        expect(test_obj.list(path: BackupEngine::Pathname.new('foo'))).to eq(['foo/bar'].map { |p| BackupEngine::Pathname.new(p) })
        expect(test_obj.list(path: BackupEngine::Pathname.new('foo/bar'))).to eq(['foo/bar/foobar', 'foo/bar/foobaz'].map { |p| BackupEngine::Pathname.new(p) })
      end

      it 'supports depth' do
        expect(test_obj.list(path: BackupEngine::Pathname.new('foo'), depth: 2)).to eq(['foo/bar/foobar', 'foo/bar/foobaz'].map { |p| BackupEngine::Pathname.new(p) })
      end

      it 'uses the cache' do
        expect(test_obj.list(path: BackupEngine::Pathname.new('foo'))).to eq(['foo/bar'].map { |p| BackupEngine::Pathname.new(p) })
        mock_s3.seed_object(bucket: bucket, key: 'foo/baz', body: '', last_modified: Time.now, storage_class: storage_class)
        expect(test_obj.list(path: BackupEngine::Pathname.new('foo'))).to eq(['foo/bar'].map { |p| BackupEngine::Pathname.new(p) })
      end
    end

    describe '.upload' do
      it 'uploads content to the bucket' do
        test_path = 'foo/bar/baz'
        test_body = SecureRandom.hex
        test_obj.upload(path: test_path, payload: test_body)

        expect(mock_s3.get_object(bucket: bucket, key: test_path)[:body]).to eq(test_body)
      end

      it 'Uses the correct storage class' do
        test_path = 'foo/bar/baz'
        test_obj.upload(path: test_path, payload: '')

        expect(mock_s3.get_object(bucket: bucket, key: test_path)[:storage_class]).to eq(storage_class)
      end

      it 'Updates the cache' do
        test_path = 'foo/bar/baz'

        # Cache must have something in it otherwise it will try and seed each call
        mock_s3.seed_object(bucket: bucket, key: '/unrelated/key', body: '', last_modified: Time.now, storage_class: storage_class)

        expect(test_obj.exists?(path: test_path)).to eq false
        test_obj.upload(path: test_path, payload: '')
        expect(test_obj.exists?(path: test_path)).to eq true
      end
    end
  end
end
