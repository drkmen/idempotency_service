local key = KEYS[1]
local fp = ARGV[1]
local token = ARGV[2]
local ttl = tonumber(ARGV[3])
if redis.call('exists', key) == 0 then
  redis.call('hmset', key, 'fingerprint', fp, 'token', token, 'committed', '0')
  redis.call('expire', key, ttl)
  return {'first', token}
else
  local stored_fp = redis.call('hget', key, 'fingerprint')
  if stored_fp == fp then
    local committed = redis.call('hget', key, 'committed')
    if committed == '1' then
      return {'committed', redis.call('hget', key, 'response_status'), redis.call('hget', key, 'response_body')}
    else
      return {'inflight', redis.call('hget', key, 'token')}
    end
  else
    return {'conflict'}
  end
end
