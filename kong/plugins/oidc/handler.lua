-- Extending the Base Plugin handler is optional, as there is no real
-- concept of interface in Lua, but the Base Plugin handler's methods
-- can be called from your child implementation and will print logs
-- in your `error.log` file (where all logs are printed).
local BasePlugin = require "kong.plugins.base_plugin"
local CustomHandler = BasePlugin:extend()
local utils = require("kong.plugins.oidc.utils")
local filter = require("kong.plugins.oidc.filter")
local session = require("kong.plugins.oidc.session")
--local userinfo = require("kong.plugins.oidc.userinfo")

CustomHandler.PRIORITY = 1000

-- Your plugin handler's constructor. If you are extending the
-- Base Plugin handler, it's only role is to instanciate itself
-- with a name. The name is your plugin name as it will be printed in the logs.
function CustomHandler:new()
  CustomHandler.super.new(self, "oidc")
end

function CustomHandler:access(config)
  -- Eventually, execute the parent implementation
  -- (will log that your plugin is entering this context)
  CustomHandler.super.access(self)

  session.configure(config)

  local oidcConfig = utils.get_options(config, ngx)

  if filter.shouldProcessRequest(oidcConfig) then
    ngx.log(ngx.DEBUG, "In plugin CustomHandler:access calling authenticate, requested path: " .. ngx.var.request_uri)

    if tryIntrospect(oidcConfig) then

      ngx.log(ngx.DEBUG, "In plugin CustomHandler:proceeding with two legged authentication, requested path: " .. ngx.var.request_uri)

    else

      local res, err = require("resty.openidc").authenticate(oidcConfig)

      if err then
        if config.recovery_page_path then
          ngx.log(ngx.DEBUG, "Entering recovery page: " .. config.recovery_page_path)
          return ngx.redirect(config.recovery_page_path)
        end
        utils.exit(500, err, ngx.HTTP_INTERNAL_SERVER_ERROR)
      end

      if res and res.user then
        utils.injectUser(res.user)
        ngx.req.set_header("X-Userinfo", require("cjson").encode(res.user))
      end

    end

  else
    ngx.log(ngx.DEBUG, "In plugin CustomHandler:access NOT calling authenticate, requested path: " .. ngx.var.request_uri)
  end

  ngx.log(ngx.DEBUG, "In plugin CustomHandler:access Done")
end

function tryIntrospect(oidcConfig)
  
  -- If introspection endpoint is not set, the functionallity is considered as disabled
  if not oidcConfig.introspection_endpoint then
    return nil
  end
  
  local res, err = require("resty.openidc").introspect(oidcConfig)
  if err then
    return nil
  end

  return res

end

-- This module needs to return the created table, so that Kong
-- can execute those functions.
return CustomHandler
