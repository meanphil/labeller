require 'netaddr'
require 'timeout'
require 'snmp'

class PrinterDiscovery
  OID = '1.3.6.1.2.1.25.3.2.1.3.1'.freeze

  attr_reader :printers

  class <<self
    def discover!
      pd = new
      pd.start

      pd.printers
    end
  end

  def initialize
    @private_if = Socket.getifaddrs.detect { |ifaddr| ifaddr.addr.try(:ipv4_private?) }
    @ip         = @private_if.addr.ip_address
    @mask       = @private_if.netmask.ip_address
    @network    = NetAddr::IPv4Net.parse("#{@ip}/#{@mask}")
    @printers   = []

    # We need lots of file handles to send packets
    # to the entire /24.
    #
    # It would be easier to just send a broadcast UDP packet,
    # but ruby-snmp gem doesn't let us do that.
    max_fh = Process.getrlimit(:NOFILE)
    required = [ 256, @network.len + 64 ].max
    Process.setrlimit(:NOFILE, required) if max_fh < required
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
    ip_s = ip.to_s
    Timeout.timeout(10) do
      SNMP::Manager.open(host: ip_s) do |manager|
        response = manager.get(OID)
        response.each_varbind do |vb|
          return ip_s if vb.value.to_s =~ /Zebra/
        end
      end
    end
    nil
  rescue Timeout::Error
    nil
  rescue SNMP::RequestTimeout
    nil
  rescue Errno::EHOSTUNREACH, Errno::EHOSTDOWN
    nil
  end
end
