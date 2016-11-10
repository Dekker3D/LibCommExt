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

local CommExtMessage = {}
local CommExtChannel = {}

local QueueReady = false
local LibCommExtQueuePkg = Apollo.GetPackage("LibCommExtQueueQueue-1.0")
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
		self.LibPriority = 0.0 -- the most basic version right now. Any newer versions should have priority.
		self.ChannelTable = self.ChannelTable or {}
		self.Initialized = true
	end
	if self.QueueReady ~= true then
		if LibCommExtQueuePkg ~= nil and LibCommExtQueuePkg.tPackage ~= nil then
			LibCommExtQueue = LibCommExtQueuePkg.tPackage
			self.QueueReady = true
		end
	end
	if self.QueueReady == true and self.Initialized == true then self.Ready = true end
end

function LibcommExt:HandleQueue(queue, remainingChars)
	
end

function LibCommExt:GetChannel(channelName)
	if channelName == nil or type(channelName) ~= "string" then return end
	if self.ChannelTable[channelName] == nil then
		self.ChannelTable[channelName] = CommExtChannel:new(channelName)
	end
	return self.ChannelTable[channelName]
end

function CommExtMessage:new(o)
	o = o or {}
    setmetatable(o, self)
    self.__index = self
	return o
end

function CommExtMessage:GetLength()
	return
end

function CommExtChannel:new(channelName)
	if channelName == nil or type(channelName) ~= "string" then return end
	o = {}
	setmetatable(o, self)
	self.__index = self
	o.Channel = channelName
	o.QueueHandler = LibCommExt
	return o
end

function CommExtChannel:Connect()
	
end

Apollo.RegisterPackage(LibCommExt, MAJOR, MINOR, {})