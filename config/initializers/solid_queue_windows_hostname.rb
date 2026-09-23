if Gem.win_platform?
  require Rails.root.join("lib/solid_queue_windows_hostname")
  SolidQueue::Processes::Base.prepend(SolidQueueWindowsHostname)
end
