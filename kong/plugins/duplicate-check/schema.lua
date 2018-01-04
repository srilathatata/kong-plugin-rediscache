return {
  no_consumer = true,
  fields = {
    header_name = {
      type = "string",
      default = "X-Client-Request-ID"
    },
     app_id = {
      type = "string",
      default = "api-key"
    },
    cache_policy = { 
      type = "table",
      schema = {
        fields = {
          duration_in_seconds = { type = "string", required = true }
        }
      }
    },
    redis_host = { type = "string", required = true },
    redis_port = { type = "number", default = 6379 },
    redis_password = { type = "string" },
    redis_timeout = { type = "number", default = 2000 }
  }
}
--[[
curl -X POST http://localhost:8001/apis/mockbin/plugins   --data "name=rediscache"   --data "config.cache_policy
.uris=/echo,/headers"  --data "config.redis_host=localhost" --data "config.cache_policy.duration_in_seconds=3600" --data "config.header_name=X-Client-Request-ID" --data "
config.app_id=X-Client-Application-ID"; ]]