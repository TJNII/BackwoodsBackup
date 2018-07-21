require 'json'

module BackupClient
  module Stat
    class StatValues
      attr_reader :mode, :uid, :gid, :size

      def initialize(mode:, uid:, gid:, size:)
        @mode = mode
        @uid  = uid
        @gid  = gid
        @size = size
      end

      def to_hash
        {}.tap do |hash|
          instance_variables.each do |var|
            hash[var.to_s.tr('@', '')] = instance_variable_get(var)
          end
        end
      end

      def to_json(options = {})
        JSON.pretty_generate(to_hash, options)
      end
    
      def file_type
        # These masks are from inode(7).
        # TODO: Per inode(7) there are C macros for this, are they exposed in Ruby against a mode?
        case (@mode & 0170000)
        when 0140000
          return :socket
        when 0120000
          return :symbolic_link
        when 0100000
          return :file
        when 0060000
          return :block_device
        when 0040000
          return :directory
        when 0020000
          return :character_device
        when 0010000
          return :fifo
        else
          raise("Unknown mode type #{masked_mode.to_s(8)}")
        end
      end
    end

    def self.file_stat(path)
      file_stat = File.stat(path)

      # dev: filesystem device: don't care
      # ino: inode number: don't cate
      # nlink: Number of hard links: hard links not supported.  TODO: Raise exception?  Warning?
      # blksize: Size in IO blocks, using @size
      # blocks: Size in 512kb blocks, using @size
      # [amc]time: Unsupported
      StatValues.new(mode: file_stat.mode,
                     uid: file_stat.uid,
                     gid: file_stat.gid,
                     size: file_stat.size)
    end
  end
end
