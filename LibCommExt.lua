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
	if self.QueueReady ~= true then
		LibCommExtQueuePkg = Apollo.GetPackage("LibCommExtQueue-1.0")
		if LibCommExtQueuePkg ~= nil and LibCommExtQueuePkg.tPackage ~= nil then
			LibCommExtQueue = LibCommExtQueuePkg.tPackage
			self.QueueReady = true
		end
	end
	if self.QueueReady == true and self.Initialized == true then self.Ready = true end
end

function LibCommExt:GetChannel(channelName)
	if channelName == nil or type(channelName) ~= "string" then return end
	if self.ChannelTable[channelName] == nil then
		self.ChannelTable[channelName] = CommExtChannel:new(channelName)
	end
	return self.ChannelTable[channelName]
end

function CommExtChannel:new(channelName)
	if channelName == nil or type(channelName) ~= "string" then return end
	o = {}
	setmetatable(o, self)
	self.__index = self
	o.Channel = channelName
	o.Callbacks = {}
	o:Connect()
	return o
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
	table.insert(self.Callbacks, {Callback = callback, Owner = owner})
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
		self:Print(1, 'Channel ' .. channel .. ' has a bad name.')
	elseif eResult == ICCommLib.CodeEnumICCommJoinResult.Left then
		self:Print(1, 'Failed to join channel')
	elseif eResult == ICCommLib.CodeEnumICCommJoinResult.MissingEntitlement then
		self:Print(1, 'Failed to join channel')
	elseif eResult == ICCommLib.CodeEnumICCommJoinResult.NoGroup then
		self:Print(1, 'Failed to join channel')
	elseif eResult == ICCommLib.CodeEnumICCommJoinResult.NoGuild then
		self:Print(1, 'Failed to join channel')
	elseif eResult == ICCommLib.CodeEnumICCommJoinResult.TooManyChannels then
		self:Print(1, "You are in too many channels to join the TIM channel")
	else
		self:Print(1, 'Failed to join channel; join result: ' .. eResult)
	end
end

function CommExtChannel:OnMessageReceived(channel, strMessage, strSender)
	for k, v in pairs(self.Callbacks) do
		v.Callback(v.Owner, channel, strMessage, strSender)
	end
end

function CommExtChannel:SendMessage(message, version, priority)
	self:SendPrivateMessage(message, nil, version, priority)
end

function CommExtChannel:SendPrivateMessage(message, recipient, version, priority) -- secretly doubles as the non-private-message function.
	if message == nil then
		return true
	end
	if self.Comm == nil then
		self:Connect()
		return false
	elseif not self.Comm:IsReady() then
		self:Connect()
		return false
	end
	if recipient == nil then
		if self.Comm:SendMessage(message) then
			self:Print(5, "Message Sent: " .. message)
			if self.heartBeatTimer ~= nil then self.heartBeatTimer:Stop() end
			self.heartBeatTimer = ApolloTimer.Create(60.0, true, "sendHeartbeatMessage", self)
			return true
		end
	else
		if self.Comm:SendPrivateMessage(recipient, message) then
			self:Print(5, "Message Sent to " .. recipient .. ": " .. message)
			return true
		end
	end
	self:Print(5, "Message sending failed: " .. message)
	return false
end

function CommExtChannel:HandleQueue(message, remainingChars)
	if remainingChars >= message.Length then
		return message.Length
	end
	return 0
end

Apollo.RegisterPackage(LibCommExt, MAJOR, MINOR, {})