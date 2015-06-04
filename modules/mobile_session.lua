require('atf.util')

local p = require('debug/print_table') --AWIODUAILSD


local expectations   = require('expectations')
local events         = require('events')
local config         = require('config')
local functionId     = require('function_id')
local json           = require('json')
local expectations   = require('expectations')
local constants      = require('protocol_handler/ford_protocol_constants')
local Expectation    = expectations.Expectation
local Event          = events.Event
local SUCCESS        = expectations.SUCCESS
local FAILED         = expectations.FAILED
local module         = {}
local mt = { __index = { } }
function mt.__index:ExpectEvent(event, name)
  local ret = Expectation(name, self.connection)
  ret.event = event
  event_dispatcher:AddEvent(self.connection, event, ret)
  self.exp_list:Add(ret)
  return ret
end
function mt.__index:ExpectResponse(arg1, ...)
  local args = table.pack(...)
  local event = events.Event()
  if type(arg1) == 'string' then
    event.matches = function(_, data)
                      return data.rpcFunctionId == functionId[arg1] and
                             data.sessionId     == self.sessionId
                    end
  elseif type(arg1) == 'number' then
    event.matches = function(_, data)
                      return data.rpcCorrelationId == arg1 and
                             data.sessionId        == self.sessionId
                    end
  else
    error("ExpectResponse: argument 1 must be string or number")
  end
  local ret = Expectation("response to " .. arg1, self.connection)
  if #args > 0 then
    ret:ValidIf(function(self, data)
                   local arguments
                   if self.occurences > #args then
                     arguments = args[#args]
                   else
                     arguments = args[self.occurences]
                   end
                   return compareValues(arguments, data.payload, "payload")
                 end)
  end
  ret.event = event
  event_dispatcher:AddEvent(self.connection, event, ret)
  self.exp_list:Add(ret)
  return ret
end
function mt.__index:ExpectAny()
  local event = events.Event()
  event.level = 1
  event.matches = function(_, data)
                    return data.sessionId == self.sessionId
                  end
  local ret = Expectation("any unprocessed data", self.connection)
  ret.event = event
  event_dispatcher:AddEvent(self.connection, event, ret)
  self.exp_list:Add(ret)
  return ret
end
function mt.__index:ExpectNotification(funcName, ...)
  local args = table.pack(...)
  local event = events.Event()
  event.matches = function(_, data)
                    return data.rpcFunctionId == functionId[funcName] and
                           data.sessionId     == self.sessionId
                  end
  local ret = Expectation(funcName .. " notification", self.connection)
  if #args > 0 then
    ret:ValidIf(function(self, data)
                   local arguments
                   if self.occurences > #args then
                     arguments = args[#args]
                   else
                     arguments = args[self.occurences]
                   end
                   return compareValues(arguments, data.payload, "payload")
                 end)
  end
  ret.event = event
  event_dispatcher:AddEvent(self.connection, event, ret)
  self.exp_list:Add(ret)
  return ret
end
function mt.__index:Send(message)
  if not message.serviceType then
    error("MobileSession:Send: sessionId must be specified")
  end
  if not message.frameInfo then
    error("MobileSession:Send: frameInfo must be specified")
  end
  self.messageId = self.messageId + 1
  self.connection:Send(
  {
    {
      version          = message.version or self.version,
      encryption       = message.encryption or false,
      frameType        = message.frameType or 1,
      serviceType      = message.serviceType,
      frameInfo        = message.frameInfo,
      sessionId        = self.sessionId,
      messageId        = self.messageId,
      rpcType          = message.rpcType,
      rpcFunctionId    = message.rpcFunctionId,
      rpcCorrelationId = message.rpcCorrelationId,
      payload          = message.payload,
      binaryData       = message.binaryData
    }
  })
end
function mt.__index:StartStreaming(service, filename, bandwidth)
  self.connection:StartStreaming(self.sessionId, service, filename, bandwidth)
end
function mt.__index:StopStreaming(filename)
  self.connection:StopStreaming(filename)
end
function mt.__index:SendRPC(func, arguments, fileName)
  self.correlationId = self.correlationId + 1
  local msg =
  {
    serviceType      = 7,
    frameInfo        = 0,
    rpcType          = 0,
    rpcFunctionId    = functionId[func],
    rpcCorrelationId = self.correlationId,
    payload          = json.encode(arguments)
  }
  if fileName then
    local f = assert(io.open(fileName))
    msg.binaryData = f:read("*all")
    io.close(f)
  end
  self:Send(msg)
  return self.correlationId
end
function mt.__index:StartService(service)
  if service ~= 7 and self.sessionId == 0 then error("Session cannot be started") end
  local startSession =
  {
    frameType   = 0,
    serviceType = service,
    frameInfo   = 1,
    sessionId   = self.sessionId,
  }
  self:Send(startSession)
  -- prepare event to expect
  local startserviceEvent = Event()
  startserviceEvent.matches = function(_, data)
                                return data.frameType   == 0 and
                                       data.serviceType == service and
                                      (service == 7 or data.sessionId   == self.sessionId) and
                                      (data.frameInfo  == 2 or  -- Start Service ACK
                                       data.frameInfo  == 3)    -- Start Service NACK
                                end

  local ret = self:ExpectEvent(startserviceEvent, "StartService ACK")
    :ValidIf(function(s, data)
               if data.frameInfo == 2 then return true
               else return false, "StartService NACK received" end
             end)
  if service == 7 then
    ret:Do(function(s, data)
             if s.status == FAILED then return end
             self.sessionId = data.sessionId
             self.hashCode = data.binaryData
           end)
  end
  return ret
end
function mt.__index:StopService(service)
  local stopService =
  self:Send(
    {
      frameType   = 0,
      serviceType = service,
      frameInfo   = 4,
      sessionId   = self.sessionId,
      binaryData  = self.hashCode,
    })
  local event = Event()
  -- prepare event to expect
  event.matches = function(_, data)
                    return data.frameType   == 0 and
                           data.serviceType == service and
                          (service == 7 or data.sessionId == self.sessionId) and
                          (data.frameInfo   == 5 or -- End Service ACK
                           data.frameInfo   == 6)   -- End Service NACK
                  end


  local ret = self:ExpectEvent(event, "EndService ACK")
    :ValidIf(function(s, data)
               if data.frameInfo == 5 then return true
               else return false, "EndService NACK received" end
             end)
  if service == 7 then self:StopHeartbeat() end
  return ret
end

function mt.__index:StopHeartbeat()
  if self.heartbeatToSDLTimer and self.heartbeatFromSDLTimer then 
    self.heartbeatEnabled = false
    self.heartbeatToSDLTimer:stop()
    self.heartbeatFromSDLTimer:stop()
  end
end

function mt.__index:StartHeartbeat()
  if self.heartbeatToSDLTimer and self.heartbeatFromSDLTimer then 
    self.heartbeatEnabled = true
    self.heartbeatToSDLTimer:start(config.heartbeatTimeout)
    self.heartbeatFromSDLTimer:start(config.heartbeatTimeout + 1000)
  end
end

function mt.__index:SetHeartbeatTimeout(timeout)
  if self.heartbeatToSDLTimer and self.heartbeatFromSDLTimer then 
    self.heartbeatToSDLTimer:setInterval(timeout)
    self.heartbeatFromSDLTimer:setInterval(timeout + 1000)
  end
end

function mt.__index:Start()
  return  self:StartService(7)
          :Do(function()
                -- Heartbeat
                if self.version > 2 then
                  local event = events.Event()
                  event.matches = function(s, data)
                                     return data.frameType   == constants.FRAME_TYPE.CONTROL_FRAME and 
                                            data.serviceType == constants.SERVICE_TYPE.CONTROL     and
                                            data.frameInfo   == constants.FRAME_INFO.HEARTBEAT     and 
                                            self.sessionId   == data.sessionId
                                  end
                  self:ExpectEvent(event, "Heartbeat")
                    :Pin()
                    :Times(AnyNumber())
                    :Do(function(data)
                          print("QQQ", self.sessionId)
                          if self.heartbeatEnabled and not self.answerHeartbeatFromSDL then
                            print("HB ACK", self.sessionId)
                            self:Send( { frameType   = constants.FRAME_TYPE.CONTROL_FRAME, 
                                         serviceType = constants.SERVICE_TYPE.CONTROL, 
                                         frameInfo   = constants.FRAME_INFO.HEARTBEAT_ACK } )
                          end
                        end)
              
                  local d = qt.dynamic()
                  self.heartbeatToSDLTimer = timers.Timer()
                  self.heartbeatFromSDLTimer = timers.Timer()
                  
                  function d.SendHeartbeat()                   
                    if self.heartbeatEnabled and self.sendHeartbeatToSDL then
                       print("Send HB, session ", self.sessionId)
                      self:Send( { frameType   = constants.FRAME_TYPE.CONTROL_FRAME, 
                                   serviceType = constants.SERVICE_TYPE.CONTROL, 
                                   frameInfo   = constants.FRAME_INFO.HEARTBEAT } )
                    end
                  end
                  
                  function d.CloseSession()
                    if self.heartbeatEnabled then
                      self:StopService(7)
                      self.test:FailTestCase("SDL didn't send anything for " .. self.heartbeatFromSDLTimer:interval()
                                             .. " msecs. Closing session # " .. self.sessionId)                      
                    end
                  end
                  
                  self.connection:OnInputData(function(_, msg) 
                                                if self.heartbeatEnabled and self.sessionId == msg.sessionId then 
                                                  self.heartbeatFromSDLTimer:reset() 
                                                end 
                                              end)
                  self.connection:OnMessageSent(function(sessionId)                                                 
                                                  if self.heartbeatEnabled and self.sessionId == sessionId then
                                                     self.heartbeatToSDLTimer:reset()
                                                  end
                                                end)
                  qt.connect(self.heartbeatToSDLTimer, "timeout()", d, "SendHeartbeat()")
                  qt.connect(self.heartbeatFromSDLTimer, "timeout()", d, "CloseSession()")
                  self:StartHeartbeat()            
                end                    
                
                local correlationId = self:SendRPC("RegisterAppInterface", self.regAppParams)
                self:ExpectResponse(correlationId, { success = true })
              end)
end

function mt.__index:Stop()
  self:StopService(7)
end

function module.MobileSession(test, connection, regAppParams)
  local res = { }
  res.test = test
  res.regAppParams = regAppParams
  res.connection = connection
  res.exp_list = test.expectations_list
  res.messageId  = 1
  res.sessionId  = 0
  res.correlationId = 1
  res.version = config.defaultProtocolVersion or 2
  res.hashCode = 0
  res.heartbeatEnabled = true
  res.sendHeartbeatToSDL = true
  res.answerHeartbeatFromSDL = true
  setmetatable(res, mt)
  return res
end

return module
