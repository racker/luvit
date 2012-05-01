require('helper')
local fixture = require('./fixture-tls')
local tls = require('tls')

local options = {
  cert = fixture.certPem,
  key = fixture.keyPem
}

local connections = 0

-- create server
local server
server = tls.createServer(options, function(socket)
  connections = connections + 1
  socket:write("Goodbye")
  socket:destroy()
end)

-- start listening
server:listen(fixture.commonPort, function()
  local options = {
    host = '127.0.0.1',
    port = fixture.commonPort
  }

  local session1 = nil
  local client1
  client1 = tls.connect(fixture.commonPort, options, function()
    print('connect1')
    assert(client1:isSessionReused() == true, 'Session *should not* be reused.')
    session1 = client1:getSession()
  end)

  client1:on('close', function()
    print('close1')

    local opts = {
      host = '127.0.0.1',
      port = fixture.commonPort,
      session = session1,
    }
    local client2
    client2 = tls.connect(fixture.commonPort, opts, function()
      print('connect2')
      assert(client2:isSessionReused() == true, 'Session *should* be reused.')
    end)

    client2:on('close', function()
      print('close2')
      server:destroy()
    end)
  end)
end)

process:on('exit', function()
  assert(connections == 2)
end)
