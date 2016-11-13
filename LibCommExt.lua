-----------------------------------------------------------------------------------------------
-- Client Lua Script for LibCommExt
-- Copyright (c) Dekker3D. All rights reserved
-----------------------------------------------------------------------------------------------
 
require "ICComm"
require "ICCommLib"

local MAJOR, MINOR = "LibCommExt-1.0", 1
local APkg = Apollo.GetPackage(MAJOR)
if APkg and (APkg.nVersion or 0) >= MINOR then
	return -- no upgrade needed
end

local LibCommExt = APkg and APkg.tPackage or {}

local CommExtChannel = {}

local QueueReady = false
local LibCommExtQueuePkg = nil
local LibCommExtQueue = nil

---------------------------------------------------------------------------------------------------
-- Utility Functions
---------------------------------------------------------------------------------------------------

function LibCommExt:Print(strToPrint)
	if strToPrint ~= nil then
	 	Print("LibCommExt: " .. strToPrint)
	end
end

function LibCommExt:EnsureInit()
	if self.Initialized ~= true then
		self.ChannelTable = self.ChannelTable or {}
		self.Initialized = true
	end
	if LibCommExt == nil then
		LibCommExtQueuePkg = Apollo.GetPackage("LibCommExtQueue")
		if LibCommExtQueuePkg ~= nil then
			LibCommExt = LibCommExtQueuePkg.tPackage
		end
	end
	if self.Initialized == true then self.Ready = true end
end

function LibCommExt:GetChannel(channelName)
	self:EnsureInit()
	self:Print("Test")
	if channelName == nil or type(channelName) ~= "string" then return end
	if self.ChannelTable[channelName] == nil then
		self.ChannelTable[channelName] = CommExtChannel:new(channelName)
	end
	return self.ChannelTable[channelName]
end

function LibCommExt:Encode(numToEncode)
	if numToEncode == nil then
		return '-'
	end
	local b64='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	return b64:sub(numToEncode,numToEncode)
end

function LibCommExt:EncodeMore(num, amount) -- "amount" gives the number of characters to use to encode this number.
	if num == nil or amount == nil then return end
	num = num - 1
	local ret = ""
	for i=1, amount, 1 do
		ret = ret .. self:Encode((num % 64) + 1)
		num = num / 64
	end
	return ret
end

function LibCommExt:Decode(charToDecode)
	if charToDecode == '-' then
		return nil
	end
	local b64='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
	return string.find(b64, charToDecode,1)
end

function LibCommExt:DecodeMore(str, amount) -- "amount" is optional and gives the number of characters to decode. Will decode entire string otherwise.
	if str == nil then return nil end
	if amount ~= nil and type(amount) == "number" and str:len() > amount then
		str = str:sub(1, amount)
	end
	local num = 0
	local mult = 1
	for i=1, str:len(), 1 do
		num = num + (self:Decode(str:sub(i,i)) - 1) * mult
		mult = mult * 64
	end
	return num + 1
end


function CommExtChannel:new(channelName, bare)
	if channelName == nil or type(channelName) ~= "string" then return end
	o = {}
	setmetatable(o, self)
	self.__index = self
	o.Channel = channelName
	o.Bare = bare -- just send and receive, don't wrap messages in anything.
	o.Callbacks = {}
	o:Connect()
	return o
end

function CommExtChannel:Print(strToPrint)
	if strToPrint ~= nil then
	 	Print("CommExtChannel: " .. strToPrint)
	end
end

function CommExtChannel:Connect()
	if self.Channel == nil or type(self.Channel) ~= "string" or self.Channel:len() <= 0 then return end
	if self.Comm ~= nil and self.Comm:IsReady() then
		return
	end
	self.Comm = ICCommLib.JoinChannel(self.Channel, ICCommLib.CodeEnumICCommChannelType.Global)
	if self.Comm ~= nil then
		self.Comm:SetJoinResultFunction("OnJoinResult", self)
		self.Comm:SetReceivedMessageFunction("OnMessageReceived", self)
		self.Comm:SetSendMessageResultFunction("OnMessageSent", self)
		self.Comm:SetThrottledFunction("OnMessageThrottled", self)
	else
		self:Print("Failed to open channel")
	end
end

function CommExtChannel:IsReady()
	return self.Comm ~= nil and self.Comm:IsReady()
end

function CommExtChannel:AddReceiveCallback(callback, owner)
	if type(callback) == "function" then
		table.insert(self.Callbacks, {Callback = callback, Owner = owner})
	elseif type(callback) == "string" then
		table.insert(self.Callbacks, {Callback = owner[callback], Owner = owner})
	end
end

function CommExtChannel:OnJoinResult(channel, eResult)
	if eResult == ICCommLib.CodeEnumICCommJoinResult.Join then
		self:Print(string.format('Joined ICComm Channel "%s"', channel:GetName()))
		if channel:IsReady() then
			self:Print('Channel is ready to transmit')
		else
			self:Print('Channel is not ready to transmit')
		end
	elseif eResult == ICCommLib.CodeEnumICCommJoinResult.BadName then
		self:Print('Channel ' .. channel .. ' has a bad name.')
	elseif eResult == ICCommLib.CodeEnumICCommJoinResult.Left then
		self:Print('Failed to join channel')
	elseif eResult == ICCommLib.CodeEnumICCommJoinResult.MissingEntitlement then
		self:Print('Failed to join channel')
	elseif eResult == ICCommLib.CodeEnumICCommJoinResult.NoGroup then
		self:Print('Failed to join channel')
	elseif eResult == ICCommLib.CodeEnumICCommJoinResult.NoGuild then
		self:Print('Failed to join channel')
	elseif eResult == ICCommLib.CodeEnumICCommJoinResult.TooManyChannels then
		self:Print("You are in too many channels to join the TIM channel")
	else
		self:Print('Failed to join channel; join result: ' .. eResult)
	end
end

function CommExtChannel:OnMessageReceived(channel, strMessage, strSender)
	for k, v in pairs(self.Callbacks) do
		v.Callback(v.Owner, channel, strMessage, strSender)
	end
end

function CommExtChannel:SendMessage(message, version, priority)
	self:SendPrivateMessage(nil, message, version, priority)
end

function CommExtChannel:SendPrivateMessage(recipient, message, version, priority) -- secretly doubles as the non-private-message function.
	LibCommExt:EnsureInit()
	LibCommExtQueue:AddToQueue({Message = message, Recipient = recipient, Version = version}, priority, self)
end

function CommExtChannel:SendActualMessage(message)
	if message == nil or message.Message == nil then
		return true
	end
	if self.Comm == nil then
		self:Connect()
		return false
	elseif not self.Comm:IsReady() then
		self:Connect()
		return false
	end
	if message.Recipient == nil then
		if self.Comm:SendMessage(message.Message) then
			self:Print("Message Sent: " .. message.Message)
			return true
		end
	else
		if self.Comm:SendPrivateMessage(message.Recipient, message.Message) then
			self:Print("Message Sent to " .. message.Recipient.. ": " .. message.Message)
			return true
		end
	end
	self:Print(5, "Message sending failed: " .. message)
	return false
end

function CommExtChannel:HandleQueue(message, remainingChars)
	if remainingChars >= message.Length then
		if self:SendActualMessage(message) then
			return message.Message.len()
		end
	end
	return 0
end

function CommExtChannel:Encode(numToEncode)
	return LibCommExt:Encode(numToEncode)
end

function CommExtChannel:EncodeMore(num, amount)
	return LibCommExt:EncodeMore(num, amount)
end

function CommExtChannel:Decode(charToDecode) 
	return LibCommExt:Decode(charToDecode)
end

function CommExtChannel:DecodeMore(str, amount)
	return LibCommExt:DecodeMore(str, amount)
end

LibCommExt:EnsureInit()

Apollo.RegisterPackage(LibCommExt, MAJOR, MINOR, {"LibCommExtQueue"})