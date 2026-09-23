# Solid Queue 1.7 forces Windows ANSI Socket.gethostname bytes to UTF-8.
# Ruby's Windows environment API supplies the Unicode computer name correctly.
module SolidQueueWindowsHostname
  def hostname
    @hostname ||= ENV.fetch("COMPUTERNAME") { super }.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
  end
end
