--!strict
local RunService = game:GetService("RunService")

local Packages = script.Parent.Parent
local Signal = require(Packages.Signal)
local Janitor = require(Packages.Janitor)
local NetworkerUtils = require(script.Parent.NetworkerUtils)

type NetworkTag = NetworkerUtils.NetworkTag
type RemotesContainer = NetworkerUtils.RemotesContainer

--[=[
	NetworkerClient facilitates the communication of client-sided networking and handles server networking instructions  
	@class NetworkerClient  
]=]
local NetworkerClient = {}
NetworkerClient.__index = NetworkerClient

export type NetworkerClient = typeof(setmetatable(
	{} :: {
		networkTag: NetworkTag,
		remotes: RemotesContainer,
		instanceConn: RBXScriptConnection?,
		changedSignals: { [string]: Signal.Signal<any> },
		_janitor: any,
	},
	NetworkerClient
))

--[=[
	Constructs a new NetworkerClient  
	@param networkTag NetworkTag -- The unique tag of the networker  
	@param module {} -- The class or service the networker will be communicating with  
	@return NetworkerClient  
]=]
function NetworkerClient.new(networkTag: NetworkTag, module: {}): NetworkerClient
	assert(RunService:IsClient(), "NetworkerClient can only be created on the client")

	local self = {
		networkTag = networkTag,
		changedSignals = {},
		_janitor = Janitor.new(),
	}

	setmetatable(self, NetworkerClient)

	if not RunService:IsRunning() then
		return self :: any
	end

	if typeof(networkTag) == "Instance" then
		local attributeTag = networkTag:GetAttribute(NetworkerUtils.INSTANCE_ATTRIBUTE) :: string?
		if not attributeTag then
			networkTag:GetAttributeChangedSignal(NetworkerUtils.INSTANCE_ATTRIBUTE):Wait()
			attributeTag = networkTag:GetAttribute(NetworkerUtils.INSTANCE_ATTRIBUTE) :: string?
		end

		assert(attributeTag, "NetworkerClient instance does not have a networkTag attribute")
		self.networkTag = attributeTag
	end

	local remotes = script.Parent:WaitForChild("_remotes"):WaitForChild(self.networkTag) :: RemotesContainer
	self.remotes = remotes

	self._janitor:Add(remotes.Destroying:Connect(function()
		self:destroy()
	end))

	self._janitor:Add(remotes.RemoteEvent.OnClientEvent:Connect(function(method: string, key: string, ...: any?)
		if method == NetworkerUtils.SET_TAG then
			module[key] = ...
			if self.changedSignals[key] then
				self.changedSignals[key]:Fire(module[key])
			end
			return
		end

		if module[method] then
			module[method](module, key, ...)
		end
	end))

	return self
end

--[=[
	Gets the Signal for the given key. Changed signals are used to notify the client when a value has been changed on the server using the set methods.  
	@param key string -- The key of the signal  
	@return Signal -- Returns the Signal  
]=]
function NetworkerClient.getServerChangedSignal<T>(self: NetworkerClient, key: string): Signal.Signal<T>
	if not self.changedSignals[key] then
		local signal = Signal.new()
		self.changedSignals[key] = signal
		self._janitor:Add(signal, "Destroy")
	end

	return self.changedSignals[key]
end

--[=[
	calls a method on the server.  
	@param method string -- The method to fire  
	@param ... any -- The arguments to pass to the method  
	@return ()  
]=]
function NetworkerClient.fire(self: NetworkerClient, method: string, ...: any?): ()
	if not self.remotes then
		return
	end

	if RunService:IsRunning() then
		self.remotes.RemoteEvent:FireServer(method, ...)
	end
end

--[=[
	calls a method on the server, and returns its result. 
	@param method string -- The method to fire  
	@param ... any -- The arguments to pass to the method  
	@return any? -- The result of the method
	@yields
]=]
function NetworkerClient.fetch(self: NetworkerClient, method: string, ...: any): any?
	if not self.remotes then
		return nil
	end

	if RunService:IsRunning() then
		return self.remotes.RemoteFunction:InvokeServer(method, ...)
	end

	return nil
end

--[=[
	Destroys the NetworkerClient and cleans up all connections  
	@return ()  
]=]
function NetworkerClient.destroy(self: NetworkerClient): ()
	self._janitor:Destroy()
	self.changedSignals = {}

	if self.instanceConn then
		self.instanceConn:Disconnect()
		self.instanceConn = nil
	end

	self.remotes = nil
end

return NetworkerClient
