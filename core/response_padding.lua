-- Response Padding Script for Nginx
-- Prevents traffic analysis through response size correlation
-- Requires: nginx-lua module (libnginx-mod-http-lua)
-- Usage: body_filter_by_lua_file /etc/nginx/lua/response_padding.lua;

-- Configuration
local PADDING_SIZES = {512, 1024, 2048, 4096, 8192}  -- Padding sizes in bytes
local MIN_RESPONSE_SIZE = 1024  -- Minimum response size to pad

-- Generate random padding
local function generate_padding(target_size, current_size)
    local padding_needed = target_size - current_size
    if padding_needed <= 0 then
        return ""
    end
    
    -- Generate random padding (non-printable chars to avoid detection)
    local padding = string.rep("\0", padding_needed)
    return padding
end

-- Get target padding size (randomize to prevent pattern detection)
local function get_target_size()
    math.randomseed(ngx.time() * 1000 + ngx.worker.id())
    return PADDING_SIZES[math.random(#PADDING_SIZES)]
end

-- Main body filter function (called by nginx)
local function add_padding()
    local body = ngx.arg[1]
    if not body then
        return
    end
    
    local body_size = #body
    if body_size < MIN_RESPONSE_SIZE then
        -- Pad small responses to minimum size
        local padding = generate_padding(MIN_RESPONSE_SIZE, body_size)
        ngx.arg[1] = body .. padding
    else
        -- Pad larger responses to random target size
        local target_size = get_target_size()
        if body_size < target_size then
            local padding = generate_padding(target_size, body_size)
            ngx.arg[1] = body .. padding
        end
    end
end

-- Add random delay (prevents timing correlation) - called in rewrite phase
local function add_delay()
    math.randomseed(ngx.time() * 1000 + ngx.worker.id())
    local delay = math.random(10, 50)  -- 10-50ms random delay
    ngx.sleep(delay / 1000)  -- Convert to seconds
end

-- Execute padding on body filter
add_padding()

