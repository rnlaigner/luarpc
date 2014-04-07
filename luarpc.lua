-- http://www.inf.puc-rio.br/~noemi/sd-14/trab1.html

local socket = require("socket")
local unpack = unpack or table.unpack

-- This is the main module luarpc.
local luarpc = {}

-- Lists.
local servant_list = {} -- {server, obj, iface, client_list}

-- Global namespace.
myinterface = {}

function interface(iface)
  -- Global namespace.
  myinterface = iface
end

-- TODO: Encode/decode.
--[[
oi                -- string "oi"
3                 -- double 3
a                 -- char "a"
\n                -- char de quebra de linha
\\                -- char "\"
nova\nlinha       -- string "nova
                     linha"
string\\n         -- string "string\n"
]]

function luarpc.validate_type(value, param_type)
  if param_type == "char" then
    if #value == 1 then
      return true
    end
  elseif param_type == "string" then
    if tostring(value) then
      return true
    end
  elseif param_type == "double" then
    if tonumber(value) then
      return true
    end
  elseif param_type == "void" then
    if value == "" or value == "\n" then
      return true
    end
  end

  return false
end

function luarpc.encode()
end

function luarpc.decode()
end

function luarpc.createServant(obj, interface_file)
  print("Setting up servant " .. #servant_list + 1 .. "...")

  -- tcp, bind, listen shortcut.
  local server = socket.bind("*", 0, 2048)

  -- Step by step.
  -- local server = socket.tcp()
  -- server:bind("*", 0)
  -- server:listen(2048)

  -- Options.
  server:setoption('keepalive', true)
  server:setoption('linger', {on = false, timeout = 0})
  server:setoption('tcp-nodelay', true)
  server:settimeout(0.1) -- accept/send/receive timeout

  -- Interface.
  dofile(interface_file)

  -- Servant.
  local servant = {
    server = server,
    obj = obj,
    iface = myinterface,
    client_list = {},
  }

  -- Servant list.
  table.insert(servant_list, servant)

  -- Connection info.
  local ip, port = server:getsockname()
  local port_file = "port" .. #servant_list .. ".txt"
  local file = io.open(port_file, "w")
  file:write(port .. "\n")
  file:close()
  print("Please connect on port " .. port .. " (also, you can script clients reading port number from file " .. port_file .. ")")
  print()

  return servant
end

function luarpc.waitIncoming()
  print("Waiting for clients...")

  -- Jump on protocol errors.
  local skip = false

  while true do
    for _, servant in pairs(servant_list) do
      -- Wait for new client connection on this servant.
      -- Wait for connection just a few ms.
      local client = servant.server:accept()

      -- Client connected.
      if client then
        -- Options.
        client:settimeout(10) -- send/receive timeout (line inactivity).

        -- Client list.
        table.insert(servant.client_list, client)

        -- Connection info.
        local ip, port = client:getsockname()
        print("Client connected " .. client:getpeername() .. " on port " .. port)
      end

      -- Connected client sent some data for this servant.
      -- Wait for activity just a few ms.
      local client_recv_ready_list, _, err = socket.select(servant.client_list, nil, 0.1)
      for _, client in pairs(client_recv_ready_list) do
        skip = false

        if type(client) ~= "number" then
          -- Connection info.
          local ip, port = client:getsockname()
          print("Receiving request data from client " .. client:getpeername() .. " on port " .. port)

          -- Method receive.
          print("Receiving request method...")
          local rpc_method, err = client:receive("*l")
          if err then
            local err_msg = "___ERRORPC: Receiving request method: " .. err
            print(err_msg)
            local _, err = client:send(err_msg .. "\n")
            if err then
              print("___ERRONET: Sending client ___ERRORPC notification: \"" .. err_msg .. "\": " .. err)
            end
            break
          else
            print("< request method: " .. rpc_method)
          end

          -- Validate method name.
          if servant.iface.methods[rpc_method] then
            -- Parameters receive.
            local values = {}
            local params = servant.iface.methods[rpc_method].args
            local i = 0
            for _, param in pairs(params) do
              if param.direction == "in" or param.direction == "inout" then
                i = i + 1
                print("Receiving request method \"" .. rpc_method .. "\" value " .. i .. "...")
                if param.type ~= "void" then
                  local value, err = client:receive("*l")
                  if err then
                    local err_msg = "___ERRORPC: Receiving request method \"" .. rpc_method .. "\" value " .. i .. ": " .. err
                    print(err_msg)
                    local _, err = client:send(err_msg .. "\n")
                    if err then
                      print("___ERRONET: Sending client ___ERRORPC notification: \"" .. err_msg .. "\": " .. err)
                    end
                    skip = true
                    break
                  else
                    -- Validate request types after receive.
                    if not luarpc.validate_type(value, param.type) then
                      local err_msg = "___ERRORPC: Wrong request type received for value " .. i .. " \"" .. value .. "\" for method \"" .. rpc_method .. "\" expecting type \"" .. param.type .. "\""
                      print(err_msg)
                      local _, err = client:send(err_msg .. "\n")
                      if err then
                        print("___ERRONET: Sending client ___ERRORPC notification: \"" .. err_msg .. "\": " .. err)
                      end
                      skip = true
                      break
                    end

                    -- Show request value.
                    print("< request value: " .. value)
                    -- Method params to be used when calling local object.
                    table.insert(values, value)
                  end
                else
                  -- Show request value.
                  print("< request value: void")
                end
              end
            end

            -- Call method on server.
            if not skip then
              -- One result fits all.
              local status, result = pcall(servant.obj[rpc_method], unpack(values))

              -- Separate results for multisend.
              --[[
              local packed_result = {pcall(servant.obj[rpc_method], unpack(values))}
              local status = packed_result[1]
              ]]

              if not status then
                local err_msg = "___ERRORPC: Problem calling method \"" .. rpc_method .. "\""
                print(err_msg)
                local _, err = client:send(err_msg .. "\n")
                if err then
                  print("___ERRONET: Sending client ___ERRORPC notification: \"" .. err_msg .. "\": " .. err)
                end
              else
                -- Validate response types before send?

                -- One result fits all.
                print("> response result: " .. result)
                -- Return result to client.
                local _, err = client:send(result .. "\n")
                if err then
                  print("___ERRONET: Sending response method \"" .. rpc_method .. "\" with result \"" .. result .. "\": " .. err)
                end

                -- Separate results for multisend.
                --[[
                for _, result in pairs({unpack(packed_result, 2)}) do
                  print("= response result: " .. result)
                  -- Return result to client.
                  local _, err = client:send(result .. "\n")
                  if err then
                    print("___ERRONET: Sending response method \"" .. rpc_method .. "\" with result \"" .. result .. "\": " .. err)
                  end
                end
                ]]
              end
            end
          else
            local err_msg = "___ERRORPC: Invalid request method \"" .. rpc_method .. "\""
            print(err_msg)
            local _, err = client:send(err_msg .. "\n")
            if err then
              print("___ERRONET: Sending client ___ERRORPC notification: \"" .. err_msg .. "\": " .. err)
            end
          end

          -- Terminate connection.
          client:close()
        end
      end
    end
  end
end

function luarpc.createProxy(server_address, server_port, interface_file)
  -- Proxy object.
  local pobj = {}

  -- Interface.
  dofile(interface_file)

  for rpc_method, method in pairs(myinterface.methods) do
    -- Proxied methods builder.
    pobj[rpc_method] = function(...)
      print()
      print("Params passed to proxy object when calling \"" .. rpc_method .. "\":")
      table.foreach(arg, print)
      print()

      -- Method in/out params.
      local params = myinterface.methods[rpc_method].args

      -- Validate request types before send.
      local i = 0
      for _, param in pairs(params) do
        if param.direction == "in" or param.direction == "inout" then
          i = i + 1
          local value = arg[i]
          if not luarpc.validate_type(value, param.type) then
            print("___ERRORPC: Wrong request type passed for value \"" .. value .. "\" for method \"" .. rpc_method .. "\" expecting type \"" .. param.type .. "\"")
            return false
          end
        end
      end

      -- Validate request #params.
      if arg.n ~= i then
        print("___ERRORPC: Wrong request number of arguments for method \"" .. rpc_method .. "\" expecting " .. i .. " got " .. arg.n)
        return false
      end

      -- tcp, connect shortcut.
      local client = socket.connect(server_address, server_port)

      -- Step by step.
      -- local client = socket.tcp()
      -- client:connect(server_address, server_port)

      -- Options.
      client:setoption('keepalive', true)
      client:setoption('linger', {on = false, timeout = 0})
      client:setoption('tcp-nodelay', true)
      client:settimeout(10) -- send/receive timeout

      -- Connection info.
      local ip, port = client:getsockname()
      print("Connected to " .. ip .. " on port " .. port)

      -- Send request method.
      print("Sending request method \"" .. rpc_method .. "\"...")
      local _, err = client:send(rpc_method .. "\n")
      if err then
        print("___ERRONET: Sending request method \"" .. rpc_method .. "\": " .. err)
        return false
      end

      -- Show request method.
      print("> request method: " .. rpc_method)

      -- Send request values.
      local i = 0
      for _, param in pairs(params) do
        if param.direction == "in" or param.direction == "inout" then
          i = i + 1
          local value = arg[i]
          print("Sending request method \"" .. rpc_method .. "\" value " .. i .. " \"" .. value .. "\"")
          local _, err = client:send(value .. "\n")
          if err then
            print("___ERRONET: Sending request method \"" .. rpc_method .. "\" value " .. i .. " \"" .. value .. "\": " .. err)
            return false
          end

          -- Show request value.
          print("> request value: " .. value)
        end
      end

      -- Receive response.
      local i = 0
      local values = {}
      for _, param in pairs(params) do
        if param.direction == "out" then
          i = i + 1
          print("Receiving response  method \"" .. rpc_method .. "\" value " .. i .. "...")
          if param.type ~= "void" then
            local value, err = client:receive("*l")
            if err then
              print("___ERRORPC: Receiving response  method \"" .. rpc_method .. "\" value " .. i .. ": " .. err)
              break
            else
              -- Validate response types after receive.
              if not luarpc.validate_type(value, param.type) then
                print("___ERRORPC: Wrong response type received for value " .. i .. " \"" .. value .. "\" for method \"" .. rpc_method .. "\" expecting type \"" .. param.type .. "\"")
                break
              end

              -- Show response value.
              print("< response value: " .. value)
              -- Results to be returned from proxied object.
              table.insert(values, value)
            end
          else
            -- Show response value.
            print("< response value: void")
          end
        end
      end

      -- Terminate connection.
      client:close()

      -- Return unpacked result.
      return unpack(values)
    end
  end

  return pobj
end

return luarpc
