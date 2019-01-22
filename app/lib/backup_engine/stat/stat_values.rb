require 'json'

module BackupEngine
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
        case (@mode & 0o170000)
        when 0o140000
          return :socket
        when 0o120000
          return :symbolic_link
        when 0o100000
          return :file
        when 0o060000
          return :block_device
        when 0o040000
          return :directory
        when 0o020000
          return :character_device
        when 0o010000
          return :fifo
        else
          raise("Unknown mode type #{masked_mode.to_s(8)}")
        end
      end
    end
  end
end
