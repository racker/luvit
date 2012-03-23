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

local path = require('path')
local fs = require('fs')
local ca_path = path.join(__dirname, '..', 'ca')
local certPem = fs.readFileSync(path.join(ca_path, 'server.crt'))
local keyPem = fs.readFileSync(path.join(ca_path, 'server.key.insecure'))

local caPem = fs.readFileSync(path.join(ca_path, 'ca.crt'))

local exports = {}
exports.caPem = caPem
exports.keyPem = keyPem
exports.certPem = certPem
exports.commonPort = 12456
return exports
