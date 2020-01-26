require 'socket'
require 'netaddr'
require 'timeout'

class PrinterDiscovery
  PORT = 9100
  MAGIC_COMNAND = "! U1 getvar \"device.languages\"\r\n".freeze

  attr_reader :printers

  class <<self
    def discover!
      pd = new
      pd.start

      # Hack to get rid of any lingering file handles
      GC.start; GC.start; GC.start

      pd.printers
    end
  end

  def initialize
    @private_if = Socket.getifaddrs.detect { |ifaddr| ifaddr.addr.try(:ipv4_private?) }
    @ip         = @private_if.addr.ip_address
    @mask       = @private_if.netmask.ip_address
    @network    = NetAddr::IPv4Net.parse("#{@ip}/#{@mask}")
    @printers   = []

    # The GC.start above mostly takes care of this
    # but just in case, as for a /24 we do intend on opening
    # 256 file handles
    Process.setrlimit(:NOFILE, [ 256, @network.len + 64 ].max)
  end

  def start
    @semaphore = Mutex.new
    threads = []

    spinner_chars = '/-\|'

    $stdout.print "Discovering printers... "
    $stdout.flush

    # Minus 2, because we don't want the base 
    # network address (we +1 later) or the 
    # broadcast address
    (@network.len - 2).times do |index|
      $stdout.print spinner_chars[index % 3]
      $stdout.flush

      # Not sure why it fails without this,
      # some sort of ratelimiting? We get
      # no exceptions or errors, the threads
      # just seem to do nothing at all
      sleep(0.01)

      threads << Thread.new {
        result = check(@network.nth(index + 1))

        if result
          @semaphore.synchronize {
            @printers << result
          }
        end
      }

      $stdout.print "\b"
    end

    threads.join

    if @printers.count > 0
      puts "Found #{@printers.count} printer(s)! #{@printers.to_s}"
    else
      puts "Found no printers :("
    end
  end

  def check(ip)
    s = nil
    Timeout.timeout(10) do
      s = TCPSocket.new(ip.to_s, PORT)
      s.write(MAGIC_COMNAND)
      response = s.recv(12)
      s.close
      # If we speak ZPL, then we can use this printer!
      return ip.to_s if(response =~ /zpl/)
    end
    nil
  rescue Timeout::Error
    nil
  rescue => e
    nil
  ensure
    s.close if s
    s = nil
  end
end
