require_relative 'pathname.rb'

module BackupEngine
  # Pathname replacement for paths mapped in via a Docker bind
  # Only implements functionality used by BackupEngine to avoid undexpected behavior
  class DockerBindPathname
    attr_reader :relative_path, :bind_path, :absolute_path

    def initialize(relative_path:, bind_path:)
      # NOTE: relative path is relative as far as we're concerned, but will likely be an absolute path
      @relative_path = BackupEngine::Pathname.new(relative_path)

      # Allow nil bind path, in which case the relative path will be treated as absolute
      if bind_path.nil?
        @bind_path = nil
        @absolute_path = @relative_path
      else
        @bind_path = BackupEngine::Pathname.new(bind_path)
        @absolute_path = @bind_path.join_relative(@relative_path)
      end

      raise('Nil relative path') if @relative_path.nil?
      raise('Nil absolute path') if @absolute_path.nil?
    end

    def ==(other)
      @relative_path == other.relative_path && @bind_path == other.bind_path
    end

    def <=>(other)
      @absolute_path <=> other.absolute_path
    end

    def to_s
      @relative_path.to_s
    end

    def children
      @absolute_path.children(false).map { |child| join(child) }
    end

    def join(other)
      DockerBindPathname.new(relative_path: @relative_path.join(other), bind_path: @bind_path)
    end
  end
end
