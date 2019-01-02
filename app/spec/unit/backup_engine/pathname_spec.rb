require_relative '../../spec_helper.rb'

require_relative '../../../lib/backup_engine/pathname.rb'

describe 'Backup Engine: unit' do
  describe BackupEngine::Pathname do
    describe '==' do
      it 'returns true when the two paths match' do
        expect(described_class.new('/foo') == described_class.new('/foo')).to be true # rubocop: disable Lint/UselessComparison
      end

      it 'returns false when the two paths do not match' do
        expect(described_class.new('/foo') == described_class.new('/bar')).to be false
      end
    end

    describe '.absolute?' do
      it 'returns true for absolute paths' do
        expect(described_class.new('/foo').absolute?).to be true
      end

      it 'returns false for relative paths' do
        expect(described_class.new('foo').absolute?).to be false
      end
    end

    describe '.to_s' do
      it 'returns the path as a string' do
        expect(described_class.new('/foo').to_s).to eql('/foo')
      end
    end

    describe '.to_a' do
      it 'returns the path as an array of Pathname objects' do
        [%w[/ foo bar baz], %w[. foo bar baz]].each do |test_array|
          test_path_obj = described_class.new('.')
          test_array.each do |component|
            test_path_obj = test_path_obj.join(component)
          end

          test_path_obj.to_a.each_with_index do |output_component, idx|
            expect(output_component).to be_instance_of(described_class)
            expect(output_component).to eq described_class.new(test_array[idx])
          end
        end
      end
    end

    describe '.join' do
      it 'joins two absolute paths' do
        test_output = described_class.new('/foo').join(described_class.new('/bar'))
        expect(test_output).to be_instance_of(described_class)
        expect(test_output).to eq described_class.new('/bar')
      end

      it 'joins an absolute and a relative path' do
        test_output = described_class.new('/foo').join(described_class.new('bar'))
        expect(test_output).to be_instance_of(described_class)
        expect(test_output).to eq described_class.new('/foo/bar')
      end

      it 'joins a relative and an absolute path' do
        test_output = described_class.new('foo').join(described_class.new('/bar'))
        expect(test_output).to be_instance_of(described_class)
        expect(test_output).to eq described_class.new('/bar')
      end

      it 'joins two relative paths' do
        test_output = described_class.new('foo').join(described_class.new('bar'))
        expect(test_output).to be_instance_of(described_class)
        expect(test_output).to eq described_class.new('foo/bar')
      end

      it 'removes duplicate separators' do
        expect(described_class.new('/foo/').join(described_class.new('bar'))).to eq described_class.new('/foo/bar')
      end
    end

    describe '.join_relative' do
      it 'joins two absolute paths' do
        test_output = described_class.new('/foo').join_relative(described_class.new('/bar'))
        expect(test_output).to be_instance_of(described_class)
        expect(test_output).to eq described_class.new('/foo/bar')
      end

      it 'joins an absolute and a relative path' do
        test_output = described_class.new('/foo').join_relative(described_class.new('bar'))
        expect(test_output).to be_instance_of(described_class)
        expect(test_output).to eq described_class.new('/foo/bar')
      end

      it 'joins a relative and an absolute path' do
        test_output = described_class.new('foo').join_relative(described_class.new('/bar'))
        expect(test_output).to be_instance_of(described_class)
        expect(test_output).to eq described_class.new('foo/bar')
      end

      it 'joins two relative paths' do
        test_output = described_class.new('foo').join_relative(described_class.new('bar'))
        expect(test_output).to be_instance_of(described_class)
        expect(test_output).to eq described_class.new('foo/bar')
      end
    end

    describe '.relative_from_root' do
      # Test a few levels deep to catch implementation errors that don't show on top level paths
      it 'fails on relative paths' do
        expect { described_class.new('foo/bar/baz').relative_from_root }.to raise_exception(StandardError)
      end

      it 'Returns the path relative from root' do
        test_output = described_class.new('/foo/bar/baz').relative_from_root
        expect(test_output).to be_instance_of(described_class)
        expect(test_output).to eq described_class.new('foo/bar/baz')
      end
    end
  end
end
