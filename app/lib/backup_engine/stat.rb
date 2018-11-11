require_relative 'stat/stat_values.rb'

module BackupEngine
  module Stat
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
