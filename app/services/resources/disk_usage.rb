module Resources
  module DiskUsage
    module_function

    def ratio(record)
      used, alloc =
        case record
        when AppRecord then [ record.volume_used_gb, record.volume_disk_gb ]
        when DatabaseService then [ record.disk_used_gb, record.disk_gb ]
        end
      return nil if used.nil? || alloc.to_i.zero?
      used / alloc.to_f
    end
  end
end
