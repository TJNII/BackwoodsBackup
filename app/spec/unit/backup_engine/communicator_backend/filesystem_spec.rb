require 'fileutils'
require 'securerandom'
require_relative '../../../spec_helper.rb'

require_relative '../../../../lib/backup_engine/communicator_backend/filesystem.rb'

describe 'Backup Engine: unit' do
  describe BackupEngine::CommunicatorBackend::Filesystem do
    let(:test_base_path) do
      path = Pathname.new('/tmp').join(SecureRandom.hex)
      FileUtils.mkdir_p(path)
      path
    end

    let(:test_obj) { described_class.new(base_path: test_base_path) }

    after :each do
      FileUtils.rm_rf(test_base_path)
    end

    describe '.date' do
      it 'returns the date of the object' do
        test_path = 'foo'
        FileUtils.touch(test_base_path.join(test_path))
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
          FileUtils.mkdir_p(test_base_path.join(test_path))
        end
      end

      it 'deletes paths and subpaths' do
        test_obj.delete(path: 'foo/bar')
        ['foo/bar/foobar', 'foo/bar/foobaz'].each do |test_path|
          expect(File.exist?(test_base_path.join(test_path))).to be false
        end

        ['foo/baz/foobar', 'foo/baz/foobaz'].each do |test_path|
          expect(File.exist?(test_base_path.join(test_path))).to be true
        end
      end

      it 'Does nothing if the path does not exist' do
        test_obj.delete(path: 'bogus/path')
        ['foo/bar/foobar', 'foo/bar/foobaz', 'foo/baz/foobar', 'foo/baz/foobaz'].each do |test_path|
          expect(File.exist?(test_base_path.join(test_path))).to be true
        end
      end
    end

    describe '.download' do
      it 'returns the contents of an object' do
        test_path = 'foo'
        test_body = SecureRandom.hex

        File.write(test_base_path.join(test_path), test_body)
        expect(test_obj.download(path: test_path)).to eq(test_body)
      end
    end

    describe '.exists?' do
      it 'returns true if the object exists' do
        test_path = 'foo/bar/baz'
        FileUtils.mkdir_p(test_base_path.join(test_path))
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
          FileUtils.mkdir_p(test_base_path.join(test_path))
        end
      end

      it 'returns the objects for the path' do
        expect(test_obj.list(path: Pathname.new('foo'))).to eq(['foo/bar'].map { |p| Pathname.new(p) })
        expect(test_obj.list(path: Pathname.new('foo/bar'))).to eq(['foo/bar/foobar', 'foo/bar/foobaz'].map { |p| Pathname.new(p) })
      end
    end

    describe '.upload' do
      it 'uploads content to the bucket' do
        test_path = 'foo/bar/baz'
        test_body = SecureRandom.hex
        test_obj.upload(path: test_path, payload: test_body)

        expect(File.read(test_base_path.join(test_path))).to eq(test_body)
      end
    end
  end
end
