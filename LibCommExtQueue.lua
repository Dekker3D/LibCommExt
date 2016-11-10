-----------------------------------------------------------------------------------------------
-- Client Lua Script for LibCommExtQueue
-- Copyright (c) Dekker3D. All rights reserved
-----------------------------------------------------------------------------------------------

--[[
General queue for LibCommExt. Separated for robustness, in case people use wildly different versions of LibCommExt.

To apply as a valid library for use with this queue, you must implement a HandleQueue(queue table, maximum characters to send) function that returns the amount of characters sent.
You will also likely want to have a LibPriority value or a GetLibPriority function to indicate when your library should get its turn.
]]--
 
require "ICComm"
require "ICCommLib"

local MAJOR, MINOR = "LibCommExtQueueQueue-1.0", 1
local APkg = Apollo.GetPackage(MAJOR)
if APkg and (APkg.nVersion or 0) >= MINOR then
	return -- no upgrade needed
end

local LibCommExtQueueQueue = APkg and APkg.tPackage or {}

---------------------------------------------------------------------------------------------------
-- Utility Functions
---------------------------------------------------------------------------------------------------

function LibCommExtQueue:Print(strToPrint)
	if strToPrint ~= nil then
	 	Print("LibCommExtQueue: " .. strToPrint)
	end
end

function LibCommExtQueue:EnsureInit()
	if self.Initialized == true then return end
	self.Queue = self.Queue or {}
	self.LibQueue = self.libQueue or {}
	self.Initialized = true
end

function LibcommExtQueue:AddSendingLibrary(library, priority)
	if library ~= nil and library.HandleQueue ~= nil and type(library.HandleQueue) == "function" then
		self:EnsureInit()
		table.insert(self.LibQueue, library)
		table.sort(self.LibQueue, function(a, b)
			local aPrio, bPrio = 0.0, 0.0
			if a ~= nil and a.LibPriority ~= nil and type(a.LibPriority) == "number" then aPrio = a.LibPriority end
			if a ~= nil and a.GetLibPriority ~= nil and type(a.GetLibPriority) == "function" then aPrio = a.GetLibPriority() end
			if b ~= nil and b.LibPriority ~= nil and type(b.LibPriority) == "number" then bPrio = b.LibPriority end
			if b ~= nil and b.GetLibPriority ~= nil and type(b.GetLibPriority) == "function" then bPrio = b.GetLibPriority() end
		end )
		return aPrio > bPrio
	emd
end

function LibCommExtQueue:AddToQueue(message)
	self:EnsureInit()
	if message.SendingLib ~= nil then
		table.insert(self.Queue, message)
	end
	if self.Timer == nil then -- Start sending immediately if we've run out of messages and had been waiting.
		self:MessageLoop()
		self.Timer = ApolloTimer.Create(1, true, "MessageLoop", self)
	end
end

function LibCommExtQueue:IsTableEmpty(table)
	return next(table) == nil
end

function LibCommExtQueue:MessageLoop()
	self:EnsureInit()
	if self:IsTableEmpty(self.Queue) then
		self.Timer:Stop()
		self.Timer = nil
		return
	end
	self.CharactersSent = 0
	self.RemainingCharacters = 90 -- safety margin. We don't want to get throttled, and some addons might use minimal amounts of traffic and not want this library.
	for v in ipairs(self.LibQueue) do
		self.CurrentQueueLib = v
		pcall(HandleQueue)
	end
end

function LibCommExtQueue:HandleQueue()
	if self.CurrentQueueLib ~= nil and self.CurrentQueueLib.HandleQueue ~= nil and type(self.CurrentQueueLib.HandleQueue) == "function" then
		local sent = self.CurrentQueueLib.HandleQueue(self.Queue, self.RemainingCharacters)
		local validResult = true
		if sent ~= nil and type(sent) == "number" then
			if sent > self.RemainingCharacters then validResult = false end
			self.CharactersSent = self.CharactersSent + sent
			self.RemainingCharacters = self.RemainingCharacters - sent
		else
			validResult = false
		end
		if validResult == false then
		-- remove library, it's not behaving like it should.
			local key = nil
			for k, v in pairs(self.LibQueue) do
				if v == self.CurrentQueueLib then key = k end
			end
			if key ~= nil then table.remove(self.LibQueue, key) end
		end
	end
end

Apollo.RegisterPackage(LibCommExtQueue, MAJOR, MINOR, {})