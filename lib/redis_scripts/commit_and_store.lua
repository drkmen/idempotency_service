local key = KEYS[1]
local token = ARGV[1]
local status = ARGV[2]
local body = ARGV[3]
local ttl = tonumber(ARGV[4])

if redis.call('exists', key) == 0 then
  return {'no_key'}
end

local stored_token = redis.call('hget', key, 'token')
if stored_token ~= token then
  return {'conflict'}
end

local committed = redis.call('hget', key, 'committed')
if committed == '1' then
  return {'already', redis.call('hget', key, 'response_status'), redis.call('hget', key, 'response_body')}
end

redis.call('hmset', key, 'committed', '1', 'response_status', status, 'response_body', body)
redis.call('expire', key, ttl)
return {'ok'}
