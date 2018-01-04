local BasePlugin = require "kong.plugins.base_plugin"
local DuplicateRequestHandler = BasePlugin:extend()
local responses = require "kong.tools.responses"
local req_get_method = ngx.req.get_method
local req_get_headers = ngx.req.get_headers
local redis = require "resty.redis"
local header_filter = require "kong.plugins.response-ratelimiting.header_filter"
local string_format = string.format

local function connect_to_redis(conf)
  local red = redis:new()
  
  red:set_timeout(conf.redis_timeout)
  
  local ok, err = red:connect(conf.redis_host, conf.redis_port)
  if err then
    return nil, err
  end

  if conf.redis_password and conf.redis_password ~= "" then
    local ok, err = red:auth(conf.redis_password)
    if err then
      return nil, err
    end
  end
  
  return red
end

local function red_set(premature, key, val, conf)
  local red, err = connect_to_redis(conf)
  if err then
      ngx_log(ngx.ERR, "Failed to connect to Redis: ", err)
  end

  red:init_pipeline()
  red:set(key, val)
  if conf.cache_policy.duration_in_seconds then
    red:expire(key, conf.cache_policy.duration_in_seconds)
  end
  local results, err = red:commit_pipeline()
  if err then
    ngx_log(ngx.ERR, "failed to commit the pipelined requests: ", err)
  end
end

function DuplicateRequestHandler:new()
  DuplicateRequestHandler.super.new(self, "duplicate-check")
end

function DuplicateRequestHandler:access(conf)
  DuplicateRequestHandler.super.access(self)
      local method = req_get_method()
      local cache_key = req_get_headers()[conf.header_name]
      local app_id = req_get_headers()[conf.app_id]

      local error_desc = { apiError = {errorCode = '%s',errorDescription = '%s',responseStatusCode = '%i'}}  
      local error_code = ""
      local error_description = ""
      local error_resp_code = ""
              
      -- if the client id is null then throw an error
      if not cache_key then
         ngx.log(ngx.ERR, "Header is missing with : X-Client-Request-ID")
         return responses.send(421,"Header is missing with : X-Client-Request-ID")
      end   
      
       -- if the app id is null then throw an error
      if not app_id then
         ngx.log(ngx.ERR, "Header is missing with : X-Client-Application-ID")
         return responses.send(420,"Header is missing with : X-Client-Application-ID")
      end 
      
      --if unable to connect to Redis, throw an error
      local red, err = connect_to_redis(conf)
      if err then
        ngx_log(ngx.ERR, "Unable to connect to Redis: ", err)
        return responses.send("Unable to connect to Redis: ")
      end
    
      local cached_val, err = red:get(cache_key)
         
      -- if the value exists in cache then return duplicate error message
      if cached_val and cached_val ~= ngx.null then
        ngx.log(ngx.ERR, "Duplicate Key")
        error_code = "DUPLICATE-REQUEST"
        error_description = "We received 2 requests with the same X-Client-Request-ID in a short period of time. Applies only to POST, PUT, and DELETE requests."
        error_resp_code = "409"
        return responses.send(409,string_format(error_desc, error_code, error_description,error_resp_code))
      end
    
      ngx.timer.at(0, red_set,cache_key, app_id, conf)
      ngx.log(ngx.ERR, "Stored in Redis" , cache_key)
end

function DuplicateRequestHandler:body_filter(conf)
  DuplicateRequestHandler.super.body_filter(self)
end

function DuplicateRequestHandler:header_filter(conf)
  DuplicateRequestHandler.super.header_filter(self)
end
return DuplicateRequestHandler