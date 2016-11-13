-----------------------------------------------------------------------------------------------
-- Client Lua Script for LibCommExtQueue
-- Copyright (c) Dekker3D. All rights reserved
-----------------------------------------------------------------------------------------------

--[[
General queue for LibCommExt. Separated for robustness, in case people use wildly different versions of LibCommExt.

To apply as a valid library for use with this queue, you must implement a HandleQueue(queue table, maximum characters to send) function that returns the amount of characters sent.
]]--
 
require "ICComm"
require "ICCommLib"

local MAJOR, MINOR = "LibCommExtQueue", 1
local APkg = Apollo.GetPackage(MAJOR)
if APkg and (APkg.nVersion or 0) >= MINOR then
	return -- no upgrade needed
end

local LibCommExtQueue = APkg and APkg.tPackage or {}

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
	self.Initialized = true
	self.IgnoredSenders = {}
end

function LibCommExtQueue:CheckSendingLibrary(library)
	if library == nil or library.HandleQueue == nil or type(library.HandleQueue) ~= "function" then return false end
	if self:AllowedSendingLibrary(library) == false then return false end
	return true
end

function LibCommExtQueue:AddToQueue(message, priority, sendingLib)
	self:EnsureInit()
	if self:CheckSendingLibrary(sendingLib) then
		self.SequenceNum = (self.SequenceNum or 0) + 1
		table.insert(self.Queue, {Message = message, Priority = priority, SendingLibrary = sendingLib, SequenceNum = self.SequenceNum})
		
		table.sort(self.Queue, function(a,b)
			if a == nil and b == nil then return false end
			if a == nil then return true end -- a should go at the end
			if b == nil then return false end -- b should go at the end
			if a.Priority ~= b.Priority then
				if a.Priority == nil then return true end
				if b.Priority == nil then return false end
				return a.Priority > b.Priority -- higher priority goes lower in the list
			end
			return a.SequenceNum < b.SequenceNum
		end)
		
		if self.Timer == nil then -- Start sending immediately if we've run out of messages and had been waiting.
			self:MessageLoop()
			self.Timer = ApolloTimer.Create(1, true, "MessageLoop", self)
		end
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
	for v in ipairs(self.Queue) do
		self.CurrentMessage = v
		pcall(HandleMessage)
	end
end

function LibCommExtQueue:HandleMessage()
	self:EnsureInit()
	if self.CurrentMessage ~= nil and self:CheckSendingLibrary(self.CurrentMessage.SendingLibrary) then
		local sent = self.CurrentMessage.SendingLibrary.HandleQueue(self.CurrentMessage.Message, self.RemainingCharacters)
		local validResult = true
		if sent ~= nil and type(sent) == "number" then
			if sent > self.RemainingCharacters then validResult = false end
			self.CharactersSent = self.CharactersSent + sent
			self.RemainingCharacters = self.RemainingCharacters - sent
		else
			validResult = false
		end
		if validResult == false then
			table.insert(self.IgnoredSenders, self.CurrentMessage.SendingLibrary)
			self:FilterList(table, function(item) return not self:AllowedSendingLibrary(item) end)
		end
	end
end

function LibCommExtQueue:AllowedSendingLibrary(item)
	if item == nil or item.SendingLibrary == nil then return false end
	for k, v in pairs(self.FilterList) do
		if item.SendingLibrary == v then return false end
	end
	return true
end

function LibCommExtQueue:RemoveFromList(table, item)
	local key = nil
	for k, v in pairs(table) do
		if v == item then
			key = k
			break
		end
	end
	if key ~= nil then
		table.remove(table, key)
	end
end

function LibCommExtQueue:FilterList(table, func)
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

function LibCommExtQueue:RemoveMessageFromQueue(message)
	self:RemoveFromList(self.Queue, message)
end

Apollo.RegisterPackage(LibCommExtQueue, MAJOR, MINOR, {})