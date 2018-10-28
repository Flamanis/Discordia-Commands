local function messageTypeReader(id, msg)
  local mes = nil
  mes = msg.channel:getMessage(id)
  if not mes and msg.guild then
    for chan in msg.guild.textChannels:iter() do
      local sudo = chan.messages:get(id)
      if sudo then
        mes = sudo
        break
      end
    end
  end
  return mes
end

local function getId(str)
  local val = str:match("%<[@#&]!?(%d+)%>")
  if val then
    str = val
  end
  return str
end

local function channelTypeReader(id, msg)
  local chan = nil
  id = getId(id)
  chan = msg.client:getChannel(id)
  return chan
end

local function guildTypeReader(id, msg)
  return msg.client:getGuild(id)
end

local function memberTypeReader(id, msg)
  local mem = nil
  if msg.guild then
    id = getId(id)
    mem = msg.guild:getMember(id)
  end
  return mem
end

local function userTypeReader(id, msg)
  local user = nil
  id = getId(id)
  msg.client:getUser(id)
  return user
end

local function numberTypeReader(num)
  return tonumber(num)
end

local function stringTypeReader(s)
  return s
end



return {
  message = messageTypeReader,
  channel = channelTypeReader,
  number = numberTypeReader,
  string = stringTypeReader,
  guild = guildTypeReader,
  member = memberTypeReader,
  user = userTypeReader,
  
}
