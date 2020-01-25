class PrintClient
  TEMPLATE = <<-ZPL
  ^XA
  ^PQ{quantity},{pause-every},1,N
  ^CFT,20
  ^FWR,0^FO{bottom},{left}^FDABV {abv}%^FS
  ^CFA,18,10
  ^FO{bottom-0},{left}^FD{std} STD DRINKS^FS
  ^FO{bottom-1},{left}^FDVOL: {vol}ml^FS
  ^FO{bottom-2},{left}^FDBATCH: {batch}^FS
  ^FO{bottom-3},{left}^FDBOTTLED: {bottled}^FS
  ^FO{bottom-4},{left}^FDB/BEFORE: {bb}^FS
  ^XZ
  ZPL

  class <<self
    def print(params)
      data = TEMPLATE.dup

      params['quantity'] = "1" if params['action'] == 'Proof'
      params['std'] = (params['abv'].to_f * params['vol'].to_f / 1000 * 0.789).round(1).to_s

      %w{quantity pause-every abv std vol batch bottled bb}.each do |field|
        data.gsub!("{#{field}}", params[field] || 'N/A')
      end

      data.gsub!("{left}", params['left'])
      data.gsub!("{bottom}", params['bottom'])
      
      bottom = params['bottom'].to_i
      5.times do |n|
        data.gsub!("{bottom-#{n}}", (bottom - 15 - (n * 20)).to_s)
      end
  
      Timeout.timeout(5) do
        s = TCPSocket.new(params['printer'], 9100)
        s.close_read
        s.write(data)
        s.close
      end
    end
  end
end