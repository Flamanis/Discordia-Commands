local function RequireOwner(args, client, msg)
    if (msg.author.id == client.owner.id) then
        return true
    else
        return false, "This command can only be run by the owner of the bot"
    end
end

local function RequireUserPermissions(args, client, msg)
    if not msg.guild then 
        return true
    end
    if type(args) ~= 'table' then args = {args} end
    
    local perms = msg.member:getPermissions()
    for k,v in pairs(args) do
        if not perms:has(v) then 
            return false, 'Command requires user to have permission: '.. v
        end
    end
    return true
end

local preconditions = {
  RequireOwner = RequireOwner,
  RequireUserPermission = RequireUserPermissions,
  RequireUserPermissions = RequireUserPermissions
}
return preconditions