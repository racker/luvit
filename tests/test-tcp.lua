--[[

Copyright 2012 The Luvit Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

--]]

require("helper")

local TCP = require('tcp')

local PORT = 8080

local server = TCP.create_server("127.0.0.1", PORT, function (client)
  client:on("data", function (chunk)
    assert(chunk == "ping")

    client:write("pong", function (err)
      assert(err == nil)

      client:close()
    end)
  end)
end)

server:on("error", function (err)
  assert(false)
end)

local client = TCP.new()
client:connect("127.0.0.1", PORT)

client:on("connect", function ()
  client:read_start()

  client:write("ping", function (err)
    assert(err == nil)

    client:on("data", function (data)
      assert(data == "pong")

      client:close()

      -- This test is done, let's exit
      process.exit()
    end)
  end)
end)

client:on("error", function (err)
  assert(false)
end)

