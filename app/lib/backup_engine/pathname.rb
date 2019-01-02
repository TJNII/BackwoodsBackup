require 'pathname'

module BackupEngine
  # Wrapper around Pathname that adds needed functionality
  # rubocop: disable Layout/EmptyLineAfterGuardClause
  class Pathname
    # Defensive programming: Pathname::SEPARATOR_LIST isn't documented, and is "/" on 2.5.1 on Linux
    # However, it's named "LIST", so ensure it doesn't change between versions or become a string that needs to be split or something
    raise('INTERNAL ERROR: Pathname::SEPARATOR_LIST is not a string') unless ::Pathname::SEPARATOR_LIST.is_a?(String)
    raise('INTERNAL ERROR: Pathname::SEPARATOR_LIST is multiple characters') unless ::Pathname::SEPARATOR_LIST.length == 1
    SEPARATOR = ::Pathname::SEPARATOR_LIST

    def initialize(path)
      @wrapped_pathname = ::Pathname.new(path)
    end

    # Using method_missing to behave like ::Pathname while ensuring BackupEngine::Pathname objects are always returned, never ::Pathname objects
    def method_missing(method_name, *args, &block)
      return super unless @wrapped_pathname.respond_to?(method_name)

      ret_val = @wrapped_pathname.send(method_name, *args, &block)
      return BackupEngine::Pathname.new(ret_val) if ret_val.is_a?(::Pathname)
      return ret_val.map { |c| c.is_a?(::Pathname) ? BackupEngine::Pathname.new(c) : c } if ret_val.is_a?(Array)
      return ret_val
    end

    def respond_to_missing?(method_name, *)
      @wrapped_pathname.respond_to?(method_name) || super
    end

    def ==(other)
      @wrapped_pathname == other.instance_variable_get('@wrapped_pathname')
    end

    def <=>(other)
      @wrapped_pathname <=> other.instance_variable_get('@wrapped_pathname')
    end

    # Override absolute? as Pathname.absolute? uses regexes which fail on non-UTF-8 parsible files
    def absolute?
      to_a[0].to_s == SEPARATOR
    end

    # This is used frequently, memoize for speed
    def to_a
      @to_a ||= _to_a
    end

    def to_s
      @wrapped_pathname.to_s
    end

    # Override join() as Pathname.join() fails on non-UTF-8 parsible files
    def join(other)
      other_obj = BackupEngine::Pathname.new(other)
      return other_obj if other_obj.absolute? # Match functionality

      our_path = to_path
      our_path.chop! if our_path[-1] == SEPARATOR # If self ends with a / omit it from the join path, otherwise the path will contain //
      BackupEngine::Pathname.new(our_path + SEPARATOR + other_obj.to_path)
    end

    # By default Pathname.new('/foo').join(Pathname.join('/bar') returns /bar
    # This method returns '/foo/bar'
    def join_relative(other)
      return join(other) unless other.absolute?
      join(other.relative_from_root)
    end

    # Returns a relative path from root, i.e. Pathname('/foo').relative_from_root will return 'foo'
    def relative_from_root
      # Don't use relative_path_from as it fails on non-UTF-8 parsible files
      raise('relative_from_root called on non-absolute path') unless absolute?
      return BackupEngine::Pathname.new(to_a[1..-1].map(&:to_path).join(SEPARATOR))
    end

    private

    def _to_a
      split_path = split
      return [split_path[0]] if split_path[0] == split_path[1]
      return split_path[0].to_a + [split_path[1]]
    end
  end
  # rubocop: enable Layout/EmptyLineAfterGuardClause
end
