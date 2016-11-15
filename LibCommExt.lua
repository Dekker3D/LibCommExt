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

---------------------------------------------------------------------------------------------------
-- LibCommExt Functions
---------------------------------------------------------------------------------------------------

function LibCommExt:Print(strToPrint)
	if strToPrint ~= nil then
	 	Print("LibCommExt: " .. strToPrint)
	end
end

function LibCommExt:EnsureInit()
	if self.Initialized ~= true then
		self.ChannelTable = self.ChannelTable or {}
		setmetatable(self.ChannelTable, {__mode = "v"})
		self.Queue = self.Queue or {}
		self.Initialized = true
	end
	if self.Initialized == true then self.Ready = true end
end

function LibCommExt:GetChannel(channelName)
	self:EnsureInit()
	if channelName == nil or type(channelName) ~= "string" then return end
	if self.ChannelTable[channelName] == nil then
		self.ChannelTable[channelName] = CommExtChannel:new(channelName)
	end
	return self.ChannelTable[channelName]
end

function LibCommExt:AddToQueue(message)
	self:EnsureInit()
	self.SequenceNum = (self.SequenceNum or 0) + 1
	message.SequenceNum = self.SequenceNum
	table.insert(self.Queue, message)
	
--[[	table.sort(self.Queue, function(a,b)
		if a == nil and b == nil then return false end
		if a == nil then return true end -- a should go at the end
		if b == nil then return false end -- b should go at the end
		if a.Priority ~= b.Priority then
			if a.Priority == nil then return true end
			if b.Priority == nil then return false end
			return a.Priority > b.Priority -- higher priority goes lower in the list
		end
		return a.SequenceNum < b.SequenceNum
	end)]]
	
	if self.Timer == nil then -- Start sending immediately if we've run out of messages and had been waiting.
		self:MessageLoop()
		self.Timer = ApolloTimer.Create(1, true, "MessageLoop", self)
	end
end

function LibCommExt:IsTableEmpty(table)
	return next(table) == nil
end

function LibCommExt:MessageLoop()
	self:EnsureInit()
	if self:IsTableEmpty(self.Queue) then
		self.Timer:Stop()
		self.Timer = nil
		return
	end
	self.CharactersSent = 0
	self.RemainingCharacters = 90 -- safety margin. We don't want to get throttled, and some addons might use minimal amounts of traffic and not want this library.
	for _, v in ipairs(self.Queue) do
		self.CurrentMessage = v
		pcall(function() self:HandleMessage() end)
	end
end

function LibCommExt:HandleMessage()
	self:EnsureInit()
	if self.CurrentMessage ~= nil and self.CurrentMessage.Message ~= nil then
		local sent = self.CurrentMessage.SendingLibrary:HandleQueue(self.CurrentMessage, self.RemainingCharacters)
		self.CharactersSent = self.CharactersSent + sent
		self.RemainingCharacters = self.RemainingCharacters - sent
		if sent > 0 then
			self:RemoveFromList(self.Queue, self.CurrentMessage)
		end
	end
end

function LibCommExt:RemoveFromList(targetTable, item)
	local key = nil
	for k, v in pairs(targetTable) do
		if v == item then
			key = k
			break
		end
	end
	if key ~= nil then
		table.remove(targetTable, key)
	end
end

function LibCommExt:FilterList(table, func)
	local keysArray = {}
	local keysTable = {}
	for k, v in pairs(table) do
		if func(v) then
			if type(k) == "number" then
				table.insert(keysArray, k)
			else
				table.insert(keysTable, k)
			end
		end
	end
	for k, v in pairs(keysTable) do
		table[v] = nil
	end
	table.sort(keysArray, function(a,b) return a > b end)
	for v in ipairs(keysArray) do
		table.remove(table, v) -- remove in reverse order.
	end
end

function LibCommExt:RemoveMessageFromQueue(message)
	self:RemoveFromList(self.Queue, message)
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


---------------------------------------------------------------------------------------------------
-- CommExtChannel Functions
---------------------------------------------------------------------------------------------------


function CommExtChannel:new(channelName, commExtVersion)
	if channelName == nil or type(channelName) ~= "string" then return end
	o = {}
	setmetatable(o, self)
	self.__index = self
	o.Channel = channelName
	o.CommExtVersion = commExtVersion -- 0 is bare messages, anything else will implement some fancy functionality.
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

function CommExtChannel:SetReceiveEcho(callback, owner)
	self.Comm:SetReceivedMessageFunction(callback, owner)
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
	LibCommExt:AddToQueue({Message = message, Recipient = recipient, Version = version, Priority = priority, SendingLibrary = self})
	--self:SendActualMessage({Message = message, Recipient = recipient, Version = version})
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
	if remainingChars >= message.Message:len() then
		if self:SendActualMessage(message) then
			return message.Message:len()
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

Apollo.RegisterPackage(LibCommExt, MAJOR, MINOR, {})