require('helper')
local path = require('path')
local fixture = require(path.join(__dirname, 'fixture-tls'))
local childprocess = require('childprocess')
local tls = require('tls')

local options = {
  cert = fixture.certPem,
  key = fixture.keyPem,
  port = 5121,
  host = '0.0.0.0'
}

local conn = tls.connect(options, function()
  assert(false); -- callback should never be executed
end)
conn:on('error', function()
  print("error")
  conn:destroy();
end)
