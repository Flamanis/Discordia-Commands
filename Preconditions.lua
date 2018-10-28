local function RequireOwner(args, client, msg)
    if (msg.author.id == client.owner.id) then
        return true
    else
        return false, "This command can only be run by the owner of the bot"
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

local function RequireGuild(args,client,msg)
    return msg.guild, "Command must be run in a guild"
end


local preconditions = {
  RequireOwner = RequireOwner,
  RequireUserPermission = RequireUserPermissions,
  RequireUserPermissions = RequireUserPermissions,
  RequireBotPermissions = RequireBotPermissions,
  RequireBotPermission = RequireBotPermissions,
  RequireGuild = RequireGuild,
}
return preconditions
