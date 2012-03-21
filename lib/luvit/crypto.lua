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

local _crypto = require('_crypto')
local crypto = {}

local Signer = Object:extend()
crypto.Signer = Signer

local function split_algorithm(algorithm)

function Signer:initialize(algorithm)
  self.algorithm = algorithm
  self.data = {}
end

function Signer:update(data)
  table.insert(self.data, data)
end

function Signer:sign(private_key, output_format)
  if (private_key == nil) then
    error("No private key")
  end
  if (output_format == nil) then
    output_format = 'binary'
  end

  pkey, err = _crypto.pkey.from_pem(private_key, true)
  if (err) then
    error(err)
  end

  _crypto.sign(self.algorithm, table.concat(self.data), pkey)
end

function crypto.createSign(algorithm)
  return Signer:new(algorithm)
end

local Verify = Object:extend()
crypto.Verify = Verify

function Signer:initialize(algorithm)
  self.algorithm = algorithm
  self.data = {}
end

function Signer:update(data)
  table.insert(self.data, data)
end

function Verifier:verify(public_key, signature, signature_format)
  if (public_key == nil) then
    error("No public key")
  end
  if (output_format == nil) then
    output_format = 'binary'
  end

  pkey, err = _crypto.pkey.from_pem(public_key)
  if (err) then
    error(err)
  end

  _crypto.verify(self.algorithm, table.concat(self.data), pkey)
end

function crypto.createVerify(algorithm)
  return Verify:new(algorithm)
end

return crypto
