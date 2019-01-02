require_relative '../../spec_helper.rb'

require_relative '../../../lib/backup_engine/docker_bind_pathname.rb'

describe 'Backup Engine: unit' do
  describe BackupEngine::DockerBindPathname do
    describe 'initialize' do
      it 'initializes with an absolute bind path and an absolute relative path' do
        test_class = described_class.new(bind_path: '/foo', relative_path: '/bar/baz')
        expect(test_class.bind_path).to eq BackupEngine::Pathname.new('/foo')
        expect(test_class.relative_path).to eq BackupEngine::Pathname.new('/bar/baz')
        expect(test_class.absolute_path).to eq BackupEngine::Pathname.new('/foo/bar/baz')
      end

      it 'initializes with an absolute bind path and a relative relative path' do
        test_class = described_class.new(bind_path: '/foo', relative_path: 'bar/baz')
        expect(test_class.bind_path).to eq BackupEngine::Pathname.new('/foo')
        expect(test_class.relative_path).to eq BackupEngine::Pathname.new('bar/baz')
        expect(test_class.absolute_path).to eq BackupEngine::Pathname.new('/foo/bar/baz')
      end

      it 'initializes with a nil bind path and an absolute relative path' do
        test_class = described_class.new(bind_path: nil, relative_path: '/bar/baz')
        expect(test_class.bind_path).to be nil
        expect(test_class.relative_path).to eq BackupEngine::Pathname.new('/bar/baz')
        expect(test_class.absolute_path).to eq BackupEngine::Pathname.new('/bar/baz')
      end

      it 'initializes with a nil bind path and a relative relative path' do
        test_class = described_class.new(bind_path: nil, relative_path: 'bar/baz')
        expect(test_class.bind_path).to be nil
        expect(test_class.relative_path).to eq BackupEngine::Pathname.new('bar/baz')
        expect(test_class.absolute_path).to eq BackupEngine::Pathname.new('bar/baz')
      end
    end

    describe '.children' do
      let(:test_path) { '/app' }

      it 'properly returns an array of child paths' do
        # Sort both so the arrays should match
        test_obj = described_class.new(bind_path: '/', relative_path: test_path).children.sort
        expect(test_obj).to be_instance_of(Array)

        BackupEngine::Pathname.new(test_path).children.sort.each_with_index do |child_path, idx|
          expect(test_obj[idx]).to be_instance_of(described_class)
          expect(test_obj[idx].bind_path).to eq BackupEngine::Pathname.new('/')
          expect(test_obj[idx].relative_path).to eq(child_path)
        end
      end
    end

    describe '.join' do
      it 'joins two absolute paths' do
        test_output = described_class.new(bind_path: '/foo', relative_path: '/bar').join('/baz')
        expect(test_output).to be_instance_of(described_class)
        expect(test_output).to eq described_class.new(bind_path: '/foo', relative_path: '/baz')
      end

      it 'joins an absolute and a relative path' do
        test_output = described_class.new(bind_path: '/foo', relative_path: '/bar').join('baz')
        expect(test_output).to be_instance_of(described_class)
        expect(test_output).to eq described_class.new(bind_path: '/foo', relative_path: '/bar/baz')
      end

      it 'joins a relative and an absolute path' do
        test_output = described_class.new(bind_path: '/foo', relative_path: 'bar').join('/baz')
        expect(test_output).to be_instance_of(described_class)
        expect(test_output).to eq described_class.new(bind_path: '/foo', relative_path: '/baz')
      end

      it 'joins two relative paths' do
        test_output = described_class.new(bind_path: '/foo', relative_path: 'bar').join('baz')
        expect(test_output).to be_instance_of(described_class)
        expect(test_output).to eq described_class.new(bind_path: '/foo', relative_path: 'bar/baz')
      end
    end
  end
end
