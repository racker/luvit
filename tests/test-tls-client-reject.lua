require('helper')
local fixture = require('./fixture-tls')
local tls = require('tls')

local options = {
  cert = fixture.certPem,
  key = fixture.certKey,
  port = fixture.commonPort,
  host = '127.0.0.1',
  rejectUnauthorized = true,
}

local connectCount = 0

local server
server = tls.createServer(options, function(socket)
  connectCount = connectCount + 1
  socket:on('data', function(data)
    print(data)
    assert(data == 'ok')
  end)
end)

server:on('clientError', function(err)
  assert(false)
end)

local unauthorized = function()
  local socket = tls.connect(options, function()
    assert(socket.authorized == nil)
    socket:finish()
    rejectUnauthorized()
  end)

  socket:on('error', function(err)
    print(err)
    assert(false)
  end)

  socket:write('ok')
end

local rejectUnauthorized = function()
  local socket = tls.connect(options, function()
    assert(false)
  end)

  socket:on('error', function(err)
    print(err)
    authorized()
  end)

  socket:write('ng')
end

local authorized = function()
  local socket = tls.connect(fixture.commonPort, {
    rejectUnauthorized = true,
    ca = fixture.loadPEM('ca1-cert')
  }, function()
    assert(socket.authorized)
    socket:finish()
    server:close()
  end)
  socket:on('error', function(err)
    print(err)
    assert(false)
  end)
  socket:write('ok')
end

server:listen(fixture.commonPort, function()
  unauthorized()
end)

process:on('exit', function()
  assert(connectCount == 3)
end)
