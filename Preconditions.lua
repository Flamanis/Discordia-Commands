local function RequireOwner(args, client, msg)
    if (msg.author.id == client.owner.id) then
        return true
    else
        return false, 'This command can only be run by the owner of the bot'
    end
end

local function RequireXPermissions(user, err, args, client, msg)
    if not msg.guild then
        return true
    end
    if type(args) ~= 'table' then args = {args} end

    local perms = user:getPermissions()
    for k,v in pairs(args) do
        if not perms:has(v) then
            return false, 'Command requires '..err..' to have permission: '.. v
        end
    end
    return true
end

local function RequireUserPermissions(args, client, msg)
    return RequireXPermissions(msg.member,'user', args, client, msg)
end

local function RequireBotPermissions(args, client, msg)
    return RequireXPermissions(msg.guild and msg.guild.me,'bot', args, client, msg)
end

local function RequireGuild(args, client, msg)
    if not msg.guild then return false, 'Command must be run in a guild' end
    if not args then return true end
    if type(args) == 'table' then
      for k,v in pairs(args) do
        if v == msg.guild.id then
          return true
        end
      end
      return false, 'Command cannot be run in this guild'
    else
      return msg.guild.id == args, 'Command cannot be run in this guild'
    end
end

local function RequireNSFW(args, client, msg)
  return msg.channel.nsfw, 'Command must be run in a NSFW channel'
end

local function RequireDM(args, client, msg)
  return not msg.guild, 'Command must be run in a private channel'
end

local function RequireUser(args, client, msg)
  if type(args) == 'string' then args = {args} end
  for k,v in pairs(args) do
    if v == msg.author.id then
      return true
    end
  end
  return false, 'Command cannot be run by this user'
end



local preconditions = {
  RequireOwner = RequireOwner,
  RequireUserPermission = RequireUserPermissions,
  RequireUserPermissions = RequireUserPermissions,
  RequireBotPermissions = RequireBotPermissions,
  RequireBotPermission = RequireBotPermissions,
  RequireGuild = RequireGuild,
  RequireNSFW = RequireNSFW,
  RequireUser = RequireUser,
}
return preconditions
