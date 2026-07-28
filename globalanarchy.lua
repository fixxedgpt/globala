-- Performance-tuned ESP and aim hot paths.
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer
local GLOBAL_ANARCHY_PLACE_ID = 132640332499066
local GLOBAL_ANARCHY_UNIVERSE_ID = 10275970697
local IsGlobalAnarchy = game.PlaceId == GLOBAL_ANARCHY_PLACE_ID or game.GameId == GLOBAL_ANARCHY_UNIVERSE_ID
local Clock = os and os.clock or tick
if type(Clock) ~= "function" then
	Clock = function()
		return 0
	end
end

if not LocalPlayer then
	warn("LocalPlayer is unavailable; aborting cleanly.")
	return
end

local Mouse
pcall(function()
	Mouse = LocalPlayer:GetMouse()
end)

local Environment = _G
pcall(function()
	local CurrentEnvironment = getfenv()
	if type(CurrentEnvironment) == "table" then
		Environment = CurrentEnvironment
	end
end)

local ExistingRuntime = Environment.__MatchaAimRuntime
if type(ExistingRuntime) == "table" and type(ExistingRuntime.Unload) == "function" then
	pcall(ExistingRuntime.Unload)
end

local ExistingUi
pcall(function()
	ExistingUi = getgenv().INSui
end)
if type(ExistingUi) == "table" and type(ExistingUi.Destroy) == "function" then
	pcall(function()
		ExistingUi:Destroy()
	end)
end
pcall(function()
	if type(setrobloxinput) == "function" then
		setrobloxinput(true)
	end
end)

local Flags = {
	Running = true,
	Aimbot = false,
	AimbotActive = false,
	AutoPrediction = true,
	SilentAim = false,
	SilentFovCheck = true,
	SilentFovRadius = 80,
	SilentMaxDistance = 1800,
	TeamCheck = false,
	StickyAim = true,
	FovCheck = true,
	DrawFov = true,
	TargetParts = { "Head", "Upper Torso" },
	AimProfile = "Rifles",
	AimSmoothness = 20,
	FovRadius = 120,
	MaxAcquireDistance = 1800,
	ProjectileSpeed = 2500,
	GravityCompensation = 196.2,
	PredictionScale = 0.85,
	NetworkScale = 1,
	MaxPredictionTime = 0.65,
	PredictionProfile = "Rifle",
	FovColor = Color3.fromRGB(149, 192, 33),
	FovAlpha = 1,
	EspEnabled = false,
	EspTeamCheck = false,
	EspBox = true,
	EspBoxColor = Color3.fromRGB(235, 235, 235),
	EspBoxAlpha = 1,
	EspChams = false,
	EspChamsColor = Color3.fromRGB(180, 45, 45),
	EspChamsAlpha = 0.18,
	EspHealth = true,
	EspName = true,
	EspWeapon = true,
	EspDistance = true,
	EspSnapline = false,
	EspSnaplineColor = Color3.fromRGB(149, 192, 33),
	EspSnaplineAlpha = 0.8,
	EspTextColor = Color3.fromRGB(235, 235, 235),
	EspTextAlpha = 1,
	EspMaxDistance = 2500,
	LockedPlayerName = nil,
}

local Connections = {}
local Drawings = {}
local Win
local Lib
local SilentAim
local LockedPlayer
local SmoothedAimPosition
local SmoothedAimTargetName
local CachedAimSmoothness
local CachedAimResponseSpeed
local AimTargetCache = {}
local PlayerModelCache = {}
local CharacterModelCache = setmetatable({}, { __mode = "k" })
local CachedPlayers = Players:GetPlayers()
local CachedPlayerIndices = {}
local EspStatus = {
	Text = "off",
	LastError = nil,
}
local SilentAimStatus = {
	Text = "inactive",
}

local Runtime = {}

local function TrackConnection(Connection)
	Connections[#Connections + 1] = Connection
	return Connection
end

for Index, Player in CachedPlayers do
	CachedPlayerIndices[Player] = Index
end

TrackConnection(Players.PlayerAdded:Connect(function(Player)
	if CachedPlayerIndices[Player] then
		return
	end

	CachedPlayers[#CachedPlayers + 1] = Player
	CachedPlayerIndices[Player] = #CachedPlayers
end))

TrackConnection(Players.PlayerRemoving:Connect(function(Player)
	local Index = CachedPlayerIndices[Player]
	if not Index then
		return
	end

	local LastIndex = #CachedPlayers
	local LastPlayer = CachedPlayers[LastIndex]
	CachedPlayers[Index] = LastPlayer
	CachedPlayers[LastIndex] = nil
	CachedPlayerIndices[Player] = nil
	AimTargetCache[Player] = nil
	PlayerModelCache[Player] = nil

	if LastPlayer and LastPlayer ~= Player then
		CachedPlayerIndices[LastPlayer] = Index
	end
end))

local function TrackDrawing(DrawingObject)
	Drawings[#Drawings + 1] = DrawingObject
	return DrawingObject
end

local function ClearAimSmoothing()
	SmoothedAimPosition = nil
	SmoothedAimTargetName = nil
end

local function ClearLock()
	LockedPlayer = nil
	Flags.LockedPlayerName = nil
	ClearAimSmoothing()
end

function Runtime.Unload()
	if not Flags.Running then
		return
	end

	Flags.Running = false
	ClearLock()

	for _, Connection in Connections do
		pcall(function()
			Connection:Disconnect()
		end)
	end

	for _, DrawingObject in Drawings do
		pcall(function()
			DrawingObject:Remove()
		end)
	end

	if Win then
		pcall(function()
			Win:Destroy()
		end)
	elseif Lib and type(Lib.Destroy) == "function" then
		pcall(function()
			Lib:Destroy()
		end)
	end

	pcall(function()
		if type(setrobloxinput) == "function" then
			setrobloxinput(true)
		end
	end)

	if Environment.__MatchaAimRuntime == Runtime then
		Environment.__MatchaAimRuntime = nil
		Environment.SilentAim = nil
		Environment.UnloadDesertStormAim = nil
		Environment.UnloadGlobalAnarchyAim = nil
	end
end

Environment.__MatchaAimRuntime = Runtime

local function Clamp(Value, Minimum, Maximum)
	if Value < Minimum then
		return Minimum
	end
	if Value > Maximum then
		return Maximum
	end
	return Value
end

local function LengthSquared(Vector)
	return Vector.X * Vector.X + Vector.Y * Vector.Y + Vector.Z * Vector.Z
end

local function GetMousePosition()
	if not Mouse then
		pcall(function()
			Mouse = LocalPlayer:GetMouse()
		end)
	end

	local X = 0
	local Y = 0
	pcall(function()
		X = Mouse and Mouse.X or 0
		Y = Mouse and Mouse.Y or 0
	end)
	return Vector2.new(X, Y)
end

local CachedPingSeconds = 0
local PingUpdatedAt = -math.huge

local function GetPingSeconds()
	local Now = Clock()
	if Now - PingUpdatedAt < 0.5 then
		return CachedPingSeconds
	end
	PingUpdatedAt = Now

	if type(GetPingValue) ~= "function" then
		CachedPingSeconds = 0
		return CachedPingSeconds
	end

	local Success, Ping = pcall(GetPingValue)
	if not Success or type(Ping) ~= "number" then
		CachedPingSeconds = 0
		return CachedPingSeconds
	end

	CachedPingSeconds = Clamp(Ping / 2000, 0, 0.35)
	return CachedPingSeconds
end

local CharacterContainerNames = { "Characters", "PlayerCharacters", "PlayerModels", "ActiveCharacters", "Actors", "Entities", "Alive" }
local RootPartNames = { humanoidrootpart = true, controllerroot = true, characterroot = true, rootpart = true, characterblock = true, collisionroot = true, collider = true, root = true, body = true }
local HeadPartNames = { head = true, headhitbox = true, headbox = true, skull = true, neck = true }
local TorsoPartNames = { uppertorso = true, torso = true, lowertorso = true, chest = true, upperbody = true, body = true }
local HealthValueNames = { health = true, currenthealth = true, hitpoints = true, hp = true }
local MaxHealthValueNames = { maxhealth = true, maxhitpoints = true, maxhp = true }
local HealthAttributeNames = { "Health", "CurrentHealth", "HitPoints", "HP" }
local MaxHealthAttributeNames = { "MaxHealth", "MaxHitPoints", "MaxHP" }
local CachedCharacterContainers, CharacterContainersExpireAt = {}, -math.huge

local function SafeIsA(Instance, ClassName)
	local Success, Result = pcall(function()
		return Instance and Instance:IsA(ClassName)
	end)
	return Success and Result
end

local function GetSafeChildren(Instance)
	local Success, Children = pcall(function()
		return Instance and Instance:GetChildren()
	end)
	return Success and Children or {}
end

local function GetSafeDescendants(Instance)
	local Success, Descendants = pcall(function()
		return Instance and Instance:GetDescendants()
	end)
	if Success and Descendants then
		return Descendants
	end
	return GetSafeChildren(Instance)
end

local function FindChildSafe(Parent, Name, Recursive)
	local Success, Child = pcall(function()
		return Parent and Parent:FindFirstChild(Name)
	end)
	if Success and Child or not Recursive then
		return Success and Child or nil
	end
	for _, Descendant in GetSafeDescendants(Parent) do
		local NameSuccess, DescendantName = pcall(function()
			return Descendant.Name
		end)
		if NameSuccess and DescendantName == Name then
			return Descendant
		end
	end
	return nil
end

local function GetPropertySafe(Instance, Property)
	local Success, Value = pcall(function()
		return Instance and Instance[Property]
	end)
	return Success and Value or nil
end

local function GetAttributeSafe(Instance, Attribute)
	local Success, Value = pcall(function()
		return Instance and Instance:GetAttribute(Attribute)
	end)
	return Success and Value or nil
end

local function ModelMatchesPlayer(Model, Player)
	if not SafeIsA(Model, "Model") then
		return false
	end

	local PlayerName = GetPropertySafe(Player, "Name")
	local UserId = GetPropertySafe(Player, "UserId")
	local ModelName = GetPropertySafe(Model, "Name")
	local LowerPlayerName = PlayerName and string.lower(tostring(PlayerName))
	if (ModelName and LowerPlayerName and string.lower(tostring(ModelName)) == LowerPlayerName)
		or (ModelName and UserId and tostring(ModelName) == tostring(UserId)) then
		return true
	end

	local AssociatedPlayer
	pcall(function()
		AssociatedPlayer = Players:GetPlayerFromCharacter(Model)
	end)
	if AssociatedPlayer == Player then
		return true
	end

	local OwnerId = GetAttributeSafe(Model, "UserId") or GetAttributeSafe(Model, "PlayerUserId")
		or GetAttributeSafe(Model, "OwnerUserId")
	if OwnerId ~= nil and UserId and tostring(OwnerId) == tostring(UserId) then
		return true
	end
	local OwnerName = GetAttributeSafe(Model, "PlayerName") or GetAttributeSafe(Model, "Username")
		or GetAttributeSafe(Model, "OwnerName")
	return OwnerName ~= nil and LowerPlayerName ~= nil
		and string.lower(tostring(OwnerName)) == LowerPlayerName
end

local function GetCharacterContainers(Now)
	if Now < CharacterContainersExpireAt then
		return CachedCharacterContainers
	end

	local Containers = {}
	local Seen = {}
	for _, Name in CharacterContainerNames do
		local Container = FindChildSafe(Workspace, Name, true)
		if Container and not Seen[Container] then
			Seen[Container] = true
			Containers[#Containers + 1] = Container
		end
	end
	CachedCharacterContainers = Containers
	CharacterContainersExpireAt = Now + 2
	return Containers
end

local function FindPlayerModel(Container, Player)
	local PlayerName = GetPropertySafe(Player, "Name")
	local UserId = GetPropertySafe(Player, "UserId")
	for _, Identity in { PlayerName, UserId and tostring(UserId) or nil } do
		if Identity then
			local Match = FindChildSafe(Container, Identity, true)
			while Match and Match ~= Container do
				if SafeIsA(Match, "Model") then
					return Match
				end
				Match = GetPropertySafe(Match, "Parent")
			end
		end
	end

	for _, Child in GetSafeChildren(Container) do
		if ModelMatchesPlayer(Child, Player) then
			return Child
		end
		for _, Grandchild in GetSafeChildren(Child) do
			if ModelMatchesPlayer(Grandchild, Player) then
				return Grandchild
			end
		end
	end
	return nil
end

local function ResolvePlayerCharacter(Player, Now)
	if not Player then
		return nil
	end

	Now = Now or Clock()
	local DirectCharacter = GetPropertySafe(Player, "Character")
	if DirectCharacter and GetPropertySafe(DirectCharacter, "Parent") then
		PlayerModelCache[Player] = {
			Character = DirectCharacter,
			ExpiresAt = Now + 0.5,
		}
		return DirectCharacter
	end

	local Cached = PlayerModelCache[Player]
	if Cached and Now < Cached.ExpiresAt then
		if Cached.Character == false then
			return nil
		end
		if GetPropertySafe(Cached.Character, "Parent") then
			return Cached.Character
		end
	end

	local Character
	if IsGlobalAnarchy then
		for _, Container in GetCharacterContainers(Now) do
			Character = FindPlayerModel(Container, Player)
			if Character then
				break
			end
		end
	end
	if not Character then
		local Match = FindChildSafe(Workspace, tostring(GetPropertySafe(Player, "Name") or ""), true)
		while Match and Match ~= Workspace do
			if SafeIsA(Match, "Model") then
				Character = Match
				break
			end
			Match = GetPropertySafe(Match, "Parent")
		end
	end

	PlayerModelCache[Player] = {
		Character = Character or false,
		ExpiresAt = Now + (Character and 0.5 or 0.25),
	}
	return Character
end

local function ResolveCharacterModel(Character, Now)
	if not Character then
		return nil
	end

	Now = Now or Clock()
	local Cached = CharacterModelCache[Character]
	if Cached and Now < Cached.ExpiresAt then
		return Cached
	end

	local Humanoid
	local ControllerManager
	local NamedRoot, NamedHead, NamedTorso
	local HighestPart
	local HighestY = -math.huge
	local LargestPart
	local LargestVolume = -math.huge
	local HealthValue
	local MaxHealthValue
	local AliveValue
	local DeadValue
	local BaseParts = {}

	for _, Descendant in GetSafeDescendants(Character) do
		if SafeIsA(Descendant, "BasePart") then
			BaseParts[#BaseParts + 1] = Descendant
			local Name = string.lower(tostring(GetPropertySafe(Descendant, "Name") or ""))

			if Name == "humanoidrootpart" or (not NamedRoot and RootPartNames[Name]) then
				NamedRoot = Descendant
			end
			if Name == "head" or (not NamedHead and HeadPartNames[Name]) then
				NamedHead = Descendant
			end
			if Name == "uppertorso" or (not NamedTorso and TorsoPartNames[Name]) then
				NamedTorso = Descendant
			end

			local Position = GetPropertySafe(Descendant, "Position")
			if Position and Position.Y > HighestY then
				HighestY = Position.Y
				HighestPart = Descendant
			end
			local Size = GetPropertySafe(Descendant, "Size")
			local Volume = Size and Size.X * Size.Y * Size.Z or 0
			if Volume > LargestVolume then
				LargestVolume = Volume
				LargestPart = Descendant
			end
		elseif not Humanoid and SafeIsA(Descendant, "Humanoid") then
			Humanoid = Descendant
		elseif not ControllerManager and SafeIsA(Descendant, "ControllerManager") then
			ControllerManager = Descendant
		else
			local Name = string.lower(tostring(GetPropertySafe(Descendant, "Name") or ""))
			if not HealthValue and HealthValueNames[Name] then
				local Value = GetPropertySafe(Descendant, "Value")
				if type(Value) == "number" then
					HealthValue = Descendant
				end
			elseif not MaxHealthValue and MaxHealthValueNames[Name] then
				local Value = GetPropertySafe(Descendant, "Value")
				if type(Value) == "number" then
					MaxHealthValue = Descendant
				end
			elseif not AliveValue and Name == "alive" then
				local Value = GetPropertySafe(Descendant, "Value")
				if type(Value) == "boolean" then
					AliveValue = Descendant
				end
			elseif not DeadValue and Name == "dead" then
				local Value = GetPropertySafe(Descendant, "Value")
				if type(Value) == "boolean" then
					DeadValue = Descendant
				end
			end
		end
	end

	local ControllerRoot = ControllerManager and GetPropertySafe(ControllerManager, "RootPart")
	if not SafeIsA(ControllerRoot, "BasePart") then
		ControllerRoot = nil
	end
	local PrimaryPart = GetPropertySafe(Character, "PrimaryPart")
	if not SafeIsA(PrimaryPart, "BasePart") then
		PrimaryPart = nil
	end

	local RootPart = ControllerRoot or NamedRoot or PrimaryPart or LargestPart or BaseParts[1]
	local Head = NamedHead or HighestPart or NamedTorso or RootPart
	local UpperTorso = NamedTorso or RootPart
	Cached = {
		Character = Character,
		Humanoid = Humanoid,
		ControllerManager = ControllerManager,
		Head = Head,
		RootPart = RootPart,
		UpperTorso = UpperTorso,
		BaseParts = BaseParts,
		HealthValue = HealthValue,
		MaxHealthValue = MaxHealthValue,
		AliveValue = AliveValue,
		DeadValue = DeadValue,
		ExpiresAt = Now + ((RootPart and Head) and 0.5 or 0.15),
	}
	CharacterModelCache[Character] = Cached
	return Cached
end

local function GetCharacterHealth(Player, ModelInfo)
	if not ModelInfo then
		return 0, 100
	end

	local Humanoid = ModelInfo.Humanoid
	if Humanoid then
		local Success, Health, MaxHealth = pcall(function()
			return Humanoid.Health, Humanoid.MaxHealth
		end)
		if Success and type(Health) == "number" then
			return Health, math.max(type(MaxHealth) == "number" and MaxHealth or 100, 1)
		end
	end

	local AliveValue = GetPropertySafe(ModelInfo.AliveValue, "Value")
	local DeadValue = GetPropertySafe(ModelInfo.DeadValue, "Value")
	if AliveValue == false or DeadValue == true then
		return 0, 100
	end

	local Health, MaxHealth = GetPropertySafe(ModelInfo.HealthValue, "Value"),
		GetPropertySafe(ModelInfo.MaxHealthValue, "Value")
	for SourceIndex = 1, 3 do
		local Source = SourceIndex == 1 and ModelInfo.Character
			or (SourceIndex == 2 and ModelInfo.RootPart or Player)
		local Alive = GetAttributeSafe(Source, "Alive")
		local Dead = GetAttributeSafe(Source, "Dead")
		if Alive == false or Dead == true then
			return 0, 100
		end
		if type(Health) ~= "number" then
			for _, Name in HealthAttributeNames do
				local Value = GetAttributeSafe(Source, Name)
				if type(Value) == "number" then
					Health = Value
					break
				end
			end
		end
		if type(MaxHealth) ~= "number" then
			for _, Name in MaxHealthAttributeNames do
				local Value = GetAttributeSafe(Source, Name)
				if type(Value) == "number" then
					MaxHealth = Value
					break
				end
			end
		end
	end

	Health = type(Health) == "number" and Health or 100
	MaxHealth = type(MaxHealth) == "number" and MaxHealth or math.max(Health, 100)
	return Health, math.max(MaxHealth, 1)
end

local function GetLocalRoot()
	local Now = Clock()
	local Character = ResolvePlayerCharacter(LocalPlayer, Now)
	local ModelInfo = ResolveCharacterModel(Character, Now)
	return ModelInfo and ModelInfo.RootPart or nil
end

local function IsTeammate(Player)
	if not Flags.TeamCheck then
		return false
	end

	local Success, Result = pcall(function()
		return Player.Team ~= nil and Player.Team == LocalPlayer.Team
	end)
	return Success and Result
end

local function GetPartPosition(Part)
	local Success, Position = pcall(function()
		return Part and Part.Position
	end)
	if Success then
		return Position
	end
	return nil
end

local function ProjectToScreen(Position)
	if not Position then
		return nil, false
	end

	local Success, ScreenPosition, OnScreen = pcall(WorldToScreen, Position)
	if not Success then
		return nil, false
	end
	return ScreenPosition, OnScreen
end

local LegPartNames = { "Left Leg", "Right Leg", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg" }
local FootPartNames = { "LeftFoot", "RightFoot" }

local function FindBasePartByName(Character, BaseParts, Name)
	local Direct = FindChildSafe(Character, Name, true)
	if SafeIsA(Direct, "BasePart") then
		return Direct
	end

	local LowerName = string.lower(Name)
	for _, Part in BaseParts or {} do
		local PartName = GetPropertySafe(Part, "Name")
		if PartName and string.lower(tostring(PartName)) == LowerName then
			return Part
		end
	end
	return nil
end

local function ResolveTargetPart(Character, Head, RootPart, UpperTorso, BaseParts, MousePosition)
	MousePosition = MousePosition or GetMousePosition()
	local ClosestPart
	local ClosestDistanceSquared = math.huge
	local SeenParts = {}

	local function ConsiderPart(Part)
		if not Part or SeenParts[Part] then
			return
		end
		SeenParts[Part] = true

		if not ClosestPart then
			ClosestPart = Part
		end

		local ScreenPosition, OnScreen = ProjectToScreen(GetPartPosition(Part))
		if not OnScreen then
			return
		end

		local DeltaX = ScreenPosition.X - MousePosition.X
		local DeltaY = ScreenPosition.Y - MousePosition.Y
		local DistanceSquared = DeltaX * DeltaX + DeltaY * DeltaY
		if DistanceSquared < ClosestDistanceSquared then
			ClosestDistanceSquared = DistanceSquared
			ClosestPart = Part
		end
	end

	local SelectedParts = Flags.TargetParts
	if type(SelectedParts) ~= "table" or #SelectedParts == 0 then
		SelectedParts = { "Head" }
	end

	for _, PartName in SelectedParts do
		if PartName == "Head" then
			ConsiderPart(Head)
		elseif PartName == "Upper Torso" then
			ConsiderPart(UpperTorso)
		elseif PartName == "Stomach" or PartName == "Humanoid Root Part" then
			ConsiderPart(RootPart)
		elseif PartName == "Legs" then
			for _, LegPartName in LegPartNames do
				ConsiderPart(FindBasePartByName(Character, BaseParts, LegPartName))
			end
		elseif PartName == "Feet" then
			for _, FootPartName in FootPartNames do
				ConsiderPart(FindBasePartByName(Character, BaseParts, FootPartName))
			end
		elseif PartName == "Closest" then
			for _, Part in BaseParts or {} do
				ConsiderPart(Part)
			end
		end
	end

	return ClosestPart or Head or UpperTorso or RootPart
end

local function BuildTarget(Player, MousePosition, Now)
	if not Player or Player.Name == LocalPlayer.Name or IsTeammate(Player) then
		return nil
	end

	Now = Now or Clock()
	local Character = ResolvePlayerCharacter(Player, Now)
	if not Character then
		AimTargetCache[Player] = nil
		return nil
	end

	local Cached = AimTargetCache[Player]
	if not Cached or Cached.Character ~= Character or Now >= (Cached.ExpiresAt or -math.huge) then
		local ModelInfo = ResolveCharacterModel(Character, Now)
		if not ModelInfo then
			AimTargetCache[Player] = nil
			return nil
		end
		Cached = {
			Player = Player,
			Character = Character,
			Humanoid = ModelInfo.Humanoid,
			ControllerManager = ModelInfo.ControllerManager,
			Head = ModelInfo.Head,
			RootPart = ModelInfo.RootPart,
			UpperTorso = ModelInfo.UpperTorso,
			BaseParts = ModelInfo.BaseParts,
			HealthValue = ModelInfo.HealthValue,
			MaxHealthValue = ModelInfo.MaxHealthValue,
			AliveValue = ModelInfo.AliveValue,
			DeadValue = ModelInfo.DeadValue,
			ExpiresAt = Now + 0.5,
		}
		AimTargetCache[Player] = Cached
	end

	local Head = Cached.Head
	local RootPart = Cached.RootPart
	local UpperTorso = Cached.UpperTorso
	local Health = GetCharacterHealth(Player, Cached)
	if Health <= 0 or not RootPart or not (Head or UpperTorso) then
		if not RootPart or not (Head or UpperTorso) then
			AimTargetCache[Player] = nil
		end
		return nil
	end

	local TargetPart = ResolveTargetPart(Character, Head, RootPart, UpperTorso, Cached.BaseParts, MousePosition)
	if not TargetPart then
		return nil
	end

	Cached.TargetPart = TargetPart
	return Cached
end

local function GetLockedTarget(MousePosition)
	local Now = Clock()
	if LockedPlayer then
		return BuildTarget(LockedPlayer, MousePosition, Now)
	end

	if not Flags.LockedPlayerName then
		return nil
	end
	for _, Player in CachedPlayers do
		if Player.Name == Flags.LockedPlayerName then
			LockedPlayer = Player
			return BuildTarget(Player, MousePosition, Now)
		end
	end

	return nil
end

local function FindClosestTarget(Selection, MousePosition)
	local UseFov = Selection and Selection.FovCheck
	if UseFov == nil then
		UseFov = Flags.FovCheck
	end
	local FovRadius = (Selection and Selection.FovRadius) or Flags.FovRadius
	local MaxDistance = (Selection and Selection.MaxDistance) or Flags.MaxAcquireDistance
	MousePosition = MousePosition or GetMousePosition()
	local LocalRoot = GetLocalRoot()
	local LocalPosition = GetPartPosition(LocalRoot)
	local FovRadiusSquared = FovRadius * FovRadius
	local MaxDistanceSquared = MaxDistance * MaxDistance
	local Now = Clock()
	local ClosestTarget
	local ClosestScreenDistanceSquared = math.huge
	local ClosestWorldDistanceSquared

	for _, Player in CachedPlayers do
		local Target = BuildTarget(Player, MousePosition, Now)
		if not Target then
			continue
		end

		local TargetPosition = GetPartPosition(Target.TargetPart)
		if not TargetPosition then
			continue
		end

		local WorldDistanceSquared
		if LocalPosition then
			local WorldOffset = LocalPosition - TargetPosition
			WorldDistanceSquared = LengthSquared(WorldOffset)
			if WorldDistanceSquared > MaxDistanceSquared then
				continue
			end
		end

		local ScreenPosition, OnScreen = ProjectToScreen(TargetPosition)
		if not OnScreen then
			continue
		end

		local DeltaX = ScreenPosition.X - MousePosition.X
		local DeltaY = ScreenPosition.Y - MousePosition.Y
		local ScreenDistanceSquared = DeltaX * DeltaX + DeltaY * DeltaY
		if UseFov and ScreenDistanceSquared > FovRadiusSquared then
			continue
		end

		if ScreenDistanceSquared < ClosestScreenDistanceSquared then
			ClosestScreenDistanceSquared = ScreenDistanceSquared
			ClosestTarget = Target
			ClosestWorldDistanceSquared = WorldDistanceSquared
		end
	end

	local ClosestScreenDistance = ClosestTarget and math.sqrt(ClosestScreenDistanceSquared) or math.huge
	local ClosestWorldDistance = ClosestWorldDistanceSquared and math.sqrt(ClosestWorldDistanceSquared) or nil
	return ClosestTarget, ClosestScreenDistance, ClosestWorldDistance
end

local SilentTargetSelection = {}

local function FindSilentTarget(MousePosition)
	SilentTargetSelection.FovCheck = Flags.SilentFovCheck
	SilentTargetSelection.FovRadius = Flags.SilentFovRadius
	SilentTargetSelection.MaxDistance = Flags.SilentMaxDistance
	return FindClosestTarget(SilentTargetSelection, MousePosition)
end

local function PredictTargetPosition(Target, Origin)
	local TargetPart = Target and Target.TargetPart
	if not TargetPart then
		return nil
	end

	local Position = GetPartPosition(TargetPart)
	if not Position then
		return nil
	end
	if not Flags.AutoPrediction or not Origin then
		return Position
	end

	local ProjectileSpeed = math.max(Flags.ProjectileSpeed, 1)
	local Distance = math.sqrt(LengthSquared(Origin - Position))
	local TravelTime = Distance / ProjectileSpeed
	local NetworkTime = GetPingSeconds() * Flags.NetworkScale
	local PredictionTime = (TravelTime + NetworkTime) * Flags.PredictionScale
	PredictionTime = Clamp(PredictionTime, 0, Flags.MaxPredictionTime)

	local VelocitySuccess, Velocity = pcall(function()
		return Target.RootPart.AssemblyLinearVelocity
	end)
	if not VelocitySuccess or not Velocity then
		VelocitySuccess, Velocity = pcall(function()
			return TargetPart.Velocity
		end)
	end
	if not VelocitySuccess or not Velocity then
		Velocity = Vector3.new(0, 0, 0)
	end

	local PredictedPosition = Position + Velocity * PredictionTime
	local DropCompensation = 0.5 * Flags.GravityCompensation * PredictionTime * PredictionTime

	return PredictedPosition + Vector3.new(0, DropCompensation, 0)
end

local function UpdateSilentTargetStatus(Target, ScreenDistance, WorldDistance)
	if not Target then
		SilentAimStatus.Text = "no target"
		return
	end

	local HitboxName = "target"
	pcall(function()
		HitboxName = Target.TargetPart.Name
	end)
	SilentAimStatus.Text = HitboxName
		.. " | "
		.. tostring(math.floor((WorldDistance or 0) + 0.5))
		.. "u | "
		.. tostring(math.floor((ScreenDistance or 0) + 0.5))
		.. "px"
end

SilentAim = function(Origin)
	if not Flags.SilentAim then
		return nil
	end

	local Target, ScreenDistance, WorldDistance = FindSilentTarget()
	if not Target then
		UpdateSilentTargetStatus(nil)
		return nil
	end

	local ShotOrigin = Origin
	if not ShotOrigin then
		local Camera = Workspace.CurrentCamera
		ShotOrigin = Camera and Camera.Position
	end
	if not ShotOrigin then
		return nil
	end

	UpdateSilentTargetStatus(Target, ScreenDistance, WorldDistance)

	return PredictTargetPosition(Target, ShotOrigin), Target.TargetPart, Target.Player
end

local function LoadUiLibrary()
	local Success, Result = pcall(function()
		local Source = game:HttpGet("https://raw.githubusercontent.com/neaxusxgod-png/INS-ui/main/uilib.min.lua")
		assert(type(Source) == "string" and #Source > 0, "empty UI library response")

		local Chunk = loadstring(Source)
		assert(type(Chunk) == "function", "UI library compilation failed")

		local LoadedLibrary = Chunk()
		return LoadedLibrary or INSui
	end)

	if Success and Result then
		return Result
	end

	warn("Failed to load the UI library: " .. tostring(Result))
	return nil
end

Lib = LoadUiLibrary()
if not Lib then
	warn("No UI library is available; aborting cleanly.")
	Runtime.Unload()
	return
end

local WindowSuccess, WindowResult = pcall(function()
	return Lib:CreateWindow({
		title = "virtuosity",
		subtitle = "Global Anarchy",
		size = Vector2.new(610, 450),
		menuKey = "lbracket",
		configFolder = "virtuosity-global-anarchy",
		configName = "default",
		opacity = 1,
		gameInput = false,
		autoSave = true,
		startOpen = true,
		rounding = 0,
		rowLines = false,
		checkboxStyle = true,
		font = "Proggy",
	})
end)

if not WindowSuccess or not WindowResult then
	warn("Failed to create the UI window: " .. tostring(WindowResult))
	Runtime.Unload()
	return
end

Win = WindowResult
pcall(function()
	Win:SetTitle("virtuosity")
end)

local VirtuosityGreen = Color3.fromRGB(149, 192, 33)
local ThemeSuccess, ThemeError = pcall(function()
	Win:SetTheme({
		bg = Color3.fromRGB(17, 17, 17),
		sidebar = Color3.fromRGB(12, 12, 12),
		white = Color3.fromRGB(235, 235, 235),
		text = Color3.fromRGB(235, 235, 235),
		sub = Color3.fromRGB(145, 145, 145),
		accent = VirtuosityGreen,
		accentA = VirtuosityGreen,
		accentB = VirtuosityGreen,
		surface = Color3.fromRGB(20, 20, 20),
		surface2 = Color3.fromRGB(27, 27, 27),
		surface3 = Color3.fromRGB(38, 38, 38),
		border = Color3.fromRGB(61, 65, 76),
		trackOff = Color3.fromRGB(71, 71, 71),
		trackOn = VirtuosityGreen,
		knobOff = Color3.fromRGB(105, 105, 105),
		sliderTrack = Color3.fromRGB(71, 71, 71),
		good = VirtuosityGreen,
		bad = Color3.fromRGB(214, 72, 72),
		unsafe = Color3.fromRGB(214, 176, 72),
	})
	Win:SetRounding(0)
	Win:SetCheckboxStyle(true)
	Win:SetRowLines(false)
	Win:SetFont("Proggy")
end)

if not ThemeSuccess then
	warn("Optional UI theming failed: " .. tostring(ThemeError))
end

local AimTab = Win:Tab("AIM", "crosshair")
local AimbotSection = AimTab:Section("aimbot", "Left")
local PredictionSection = AimTab:Section("prediction", "Right")
local SilentSection = AimTab:Section("silent aim", "Right")

AimbotSection:Label("profile: Global Anarchy [132640332499066]")

local AimbotToggle = AimbotSection:Toggle("enabled", false, function(Value)
	Flags.Aimbot = Value
	if not Value then
		ClearLock()
	end
end)

AimbotToggle:AddKeybind("MouseButton2", "Hold", function(Value)
	Flags.AimbotActive = Value
	if AimbotToggle:Get() ~= Value then
		AimbotToggle:Set(Value)
	end
	if not Value then
		ClearLock()
	end
end)

AimbotSection:Toggle("Roblox team check", false, function(Value)
	Flags.TeamCheck = Value
	if Value then
		ClearLock()
	end
end)

AimbotSection:Toggle("sticky aim", true, function(Value)
	Flags.StickyAim = Value
	ClearLock()
end)

local DrawFovToggle = AimbotSection:Toggle("draw fov", Flags.DrawFov, function(Value)
	Flags.DrawFov = Value
end)

DrawFovToggle:AddColorpicker("fov color", Flags.FovColor, function(Color, Alpha)
	Flags.FovColor = Color
	Flags.FovAlpha = Alpha
end)

local TargetSection = AimTab:Section("target selection", "Left")

local FovRadiusSlider = TargetSection:Slider("fov radius", Flags.FovRadius, 1, 10, 400, "px", function(Value)
	Flags.FovRadius = Value
end)

local AcquireRangeSlider = TargetSection:Slider(
	"acquire range",
	Flags.MaxAcquireDistance,
	25,
	100,
	5000,
	"u",
	function(Value)
		Flags.MaxAcquireDistance = Value
	end
)

local SmoothnessSlider = TargetSection:Slider(
	"smoothness",
	Flags.AimSmoothness,
	1,
	0,
	100,
	"%",
	function(Value)
		Flags.AimSmoothness = Value
	end
)

local TargetHitboxDropdown = TargetSection:Dropdown(
	"target hitboxes",
	Flags.TargetParts,
	{ "Head", "Upper Torso", "Stomach", "Legs", "Feet", "Closest" },
	true,
	function(Value)
		local SelectedParts = {}
		for _, PartName in Value do
			SelectedParts[#SelectedParts + 1] = PartName
		end
		if #SelectedParts == 0 then
			SelectedParts[1] = "Head"
		end
		Flags.TargetParts = SelectedParts
	end
)

pcall(function()
	TargetHitboxDropdown:UpdateChoices({ "Head", "Upper Torso", "Stomach", "Legs", "Feet", "Closest" })
end)

local AimProfiles = {
	Rifles = {
		FovRadius = 120,
		MaxDistance = 1800,
		Hitboxes = { "Head", "Upper Torso" },
		Smoothness = 20,
	},
	Sniper = {
		FovRadius = 70,
		MaxDistance = 3500,
		Hitboxes = { "Head" },
		Smoothness = 35,
	},
	Hybrid = {
		FovRadius = 100,
		MaxDistance = 2500,
		Hitboxes = { "Head", "Upper Torso", "Stomach" },
		Smoothness = 25,
	},
}

local UpdatingAimProfile = false
local AimProfileDropdown

local function SetAimProfile(Value)
	if UpdatingAimProfile then
		return
	end

	if type(Value) ~= "table" or #Value == 0 then
		Flags.AimProfile = nil
		return
	end

	local ProfileName = Value[#Value]
	if #Value > 1 and AimProfileDropdown then
		UpdatingAimProfile = true
		AimProfileDropdown:Set({ ProfileName })
		UpdatingAimProfile = false
	end

	local Profile = AimProfiles[ProfileName]
	if not Profile then
		return
	end

	Flags.AimProfile = ProfileName
	FovRadiusSlider:Set(Profile.FovRadius)
	AcquireRangeSlider:Set(Profile.MaxDistance)
	SmoothnessSlider:Set(Profile.Smoothness)
	TargetHitboxDropdown:Set(Profile.Hitboxes)
	ClearLock()
end

AimProfileDropdown = TargetSection:Dropdown(
	"profiles",
	{ Flags.AimProfile },
	{ "Rifles", "Sniper", "Hybrid" },
	true,
	SetAimProfile
)

local AutoPredictionToggle = PredictionSection:Toggle("auto prediction", true, function(Value)
	Flags.AutoPrediction = Value
end)

local ProjectileSpeedSlider = PredictionSection:Slider(
	"projectile speed",
	Flags.ProjectileSpeed,
	25,
	50,
	5000,
	"u/s",
	function(Value)
		Flags.ProjectileSpeed = Value
	end
)

local GravitySlider = PredictionSection:Slider(
	"bullet gravity",
	Flags.GravityCompensation,
	0.1,
	0,
	250,
	"u/s2",
	function(Value)
		Flags.GravityCompensation = Value
	end
)

local PredictionScaleSlider = PredictionSection:Slider(
	"prediction scale",
	Flags.PredictionScale,
	0.05,
	0.1,
	2,
	"x",
	function(Value)
		Flags.PredictionScale = Value
	end
)

local MaxLeadSlider = PredictionSection:Slider(
	"max lead time",
	Flags.MaxPredictionTime,
	0.05,
	0.1,
	1.5,
	"s",
	function(Value)
		Flags.MaxPredictionTime = Value
	end
)

PredictionSection:Slider(
	"network compensation",
	Flags.NetworkScale,
	0.05,
	0,
	2,
	"x",
	function(Value)
		Flags.NetworkScale = Value
	end
)

local PredictionProfiles = {
	["Rifle"] = { Speed = 2500, Gravity = 196.2, Scale = 0.85, MaxLead = 0.65 },
	["SMG / subsonic"] = { Speed = 1800, Gravity = 196.2, Scale = 0.9, MaxLead = 0.75 },
	["DMR / sniper"] = { Speed = 3200, Gravity = 196.2, Scale = 0.8, MaxLead = 0.55 },
	["Fast / hitscan-like"] = { Speed = 5000, Gravity = 0, Scale = 0.55, MaxLead = 0.35 },
}

PredictionSection:Dropdown(
	"weapon profile",
	{ Flags.PredictionProfile },
	{ "Rifle", "SMG / subsonic", "DMR / sniper", "Fast / hitscan-like" },
	false,
	function(Value)
		local ProfileName = Value[1]
		local Profile = PredictionProfiles[ProfileName]
		if not Profile then
			return
		end

		Flags.PredictionProfile = ProfileName
		ProjectileSpeedSlider:Set(Profile.Speed)
		GravitySlider:Set(Profile.Gravity)
		PredictionScaleSlider:Set(Profile.Scale)
		MaxLeadSlider:Set(Profile.MaxLead)
	end
)

local SilentAimToggle = SilentSection:Toggle("silent aim", false, function(Value)
	Flags.SilentAim = Value
	if not Value then
		SilentAimStatus.Text = "inactive"
	end
end)

SilentAimToggle:AddKeybind("V", "Hold", function(Value)
	if SilentAimToggle:Get() ~= Value then
		SilentAimToggle:Set(Value)
	end
end)

SilentSection:Toggle("target fov", true, function(Value)
	Flags.SilentFovCheck = Value
end)

SilentSection:Slider("head proximity", Flags.SilentFovRadius, 1, 5, 400, "px", function(Value)
	Flags.SilentFovRadius = Value
end)

SilentSection:Slider("max range", Flags.SilentMaxDistance, 25, 100, 5000, "u", function(Value)
	Flags.SilentMaxDistance = Value
end)

SilentSection:Label(function()
	return "target: " .. SilentAimStatus.Text
end)

local EspTab = Win:Tab("ESP", "eye")
local EspPlayerSection = EspTab:Section("player esp", "Left")
local EspInfoSection = EspTab:Section("information", "Right")
local EspRangeSection = EspTab:Section("filtering", "Right")

EspPlayerSection:Toggle("enabled", false, function(Value)
	Flags.EspEnabled = Value
	EspStatus.LastError = nil
	EspStatus.Text = Value and "starting..." or "off"
end)

EspPlayerSection:Toggle("Roblox team check", false, function(Value)
	Flags.EspTeamCheck = Value
end)

local BoxToggle = EspPlayerSection:Toggle("bounding box", true, function(Value)
	Flags.EspBox = Value
end)

BoxToggle:AddColorpicker("box color", Flags.EspBoxColor, function(Color, Alpha)
	Flags.EspBoxColor = Color
	Flags.EspBoxAlpha = Alpha
end)

local ChamsToggle = EspPlayerSection:Toggle("2D chams", false, function(Value)
	Flags.EspChams = Value
end)

ChamsToggle:AddColorpicker("chams color", Flags.EspChamsColor, function(Color, Alpha)
	Flags.EspChamsColor = Color
	Flags.EspChamsAlpha = Alpha
end)

EspPlayerSection:Toggle("health bar", true, function(Value)
	Flags.EspHealth = Value
end)

local SnaplineToggle = EspPlayerSection:Toggle("snapline", false, function(Value)
	Flags.EspSnapline = Value
end)

SnaplineToggle:AddColorpicker("snapline color", Flags.EspSnaplineColor, function(Color, Alpha)
	Flags.EspSnaplineColor = Color
	Flags.EspSnaplineAlpha = Alpha
end)

local NameToggle = EspInfoSection:Toggle("name", true, function(Value)
	Flags.EspName = Value
end)

NameToggle:AddColorpicker("text color", Flags.EspTextColor, function(Color, Alpha)
	Flags.EspTextColor = Color
	Flags.EspTextAlpha = Alpha
end)

EspInfoSection:Toggle("weapon", true, function(Value)
	Flags.EspWeapon = Value
end)

EspInfoSection:Toggle("distance", true, function(Value)
	Flags.EspDistance = Value
end)

EspRangeSection:Slider("max distance", Flags.EspMaxDistance, 25, 100, 5000, "u", function(Value)
	Flags.EspMaxDistance = Value
end)

EspRangeSection:Label(function()
	return "status: " .. EspStatus.Text
end)

local SettingsTab = Win:AddSettingsTab("cog")
local ScriptSettingsSection = SettingsTab:Section("script", "Right")
ScriptSettingsSection:Button("unload script", function()
	Runtime.Unload()
end)

local EspBundles = {}
local EspTargetCache = {}
local EspWeaponCache = {}
local EspErrorReported = false
local EspRendererFailed = false
local EspFrameId = 0
local EspWasEnabled = false
local EspUpdateAccumulator = 0
local EspOutlineColor = Color3.fromRGB(0, 0, 0)
local InstanceIdentityCache = setmetatable({}, { __mode = "k" })
local ESP_UPDATE_INTERVAL = 1 / 60

local function GetInstanceIdentity(Instance)
	local CachedIdentity = InstanceIdentityCache[Instance]
	if CachedIdentity then
		return CachedIdentity
	end

	local Address = GetPropertySafe(Instance, "Address")
	CachedIdentity = type(Address) == "number" and Address > 0 and tostring(Address)
		or tostring(GetPropertySafe(Instance, "Name") or Instance)
	InstanceIdentityCache[Instance] = CachedIdentity
	return CachedIdentity
end

local function GetPlayerIdentity(Player)
	return GetInstanceIdentity(Player)
end

local LocalPlayerIdentity = GetPlayerIdentity(LocalPlayer)

local function ReportEspError(Prefix, ErrorMessage)
	local FullMessage = Prefix .. ": " .. tostring(ErrorMessage)
	EspStatus.LastError = FullMessage
	EspStatus.Text = "error: " .. string.sub(tostring(ErrorMessage), 1, 38)
	if not EspErrorReported then
			EspErrorReported = true
			warn(FullMessage)
			pcall(function()
				if type(notify) == "function" then
					notify(FullMessage, "virtuosity ESP", 8)
				end
			end)
	end
end

local function SetDrawingProperty(DrawingObject, Property, Value)
	if not DrawingObject then
		return false
	end

	local Success = pcall(function()
		DrawingObject[Property] = Value
	end)
	return Success
end

local function CreateDrawingObject(DrawingType)
	local Success, DrawingObject = pcall(function()
		return Drawing.new(DrawingType)
	end)
	if not Success or not DrawingObject then
		return nil
	end
	return TrackDrawing(DrawingObject)
end

local function SetTextDefaults(TextObject, Centered)
	SetDrawingProperty(TextObject, "Color", Flags.EspTextColor)
	SetDrawingProperty(TextObject, "FontSize", 13)
	SetDrawingProperty(TextObject, "Center", Centered)
	SetDrawingProperty(TextObject, "Outline", true)
	SetDrawingProperty(TextObject, "Visible", false)
	SetDrawingProperty(TextObject, "ZIndex", 14)
	local Font
	pcall(function()
		Font = Drawing.Fonts.UI
	end)
	if Font then
		SetDrawingProperty(TextObject, "Font", Font)
	end
end

local function CreateEspBundle()
	local Bundle = {
		BoxOutline = {},
		Box = {},
	}

	for Index = 1, 4 do
		local BoxLine = CreateDrawingObject("Line")
		if BoxLine then
			SetDrawingProperty(BoxLine, "Thickness", 1)
			SetDrawingProperty(BoxLine, "Visible", false)
			SetDrawingProperty(BoxLine, "ZIndex", 11)
			Bundle.Box[#Bundle.Box + 1] = BoxLine
		end
	end

	Bundle.Name = CreateDrawingObject("Text")
	SetTextDefaults(Bundle.Name, true)

	for Index = 1, 4 do
		local OutlineLine = CreateDrawingObject("Line")
		if OutlineLine then
			SetDrawingProperty(OutlineLine, "Thickness", 3)
			SetDrawingProperty(OutlineLine, "Color", Color3.fromRGB(0, 0, 0))
			SetDrawingProperty(OutlineLine, "Visible", false)
			SetDrawingProperty(OutlineLine, "ZIndex", 10)
			Bundle.BoxOutline[#Bundle.BoxOutline + 1] = OutlineLine
		end
	end

	Bundle.Info = CreateDrawingObject("Text")
	Bundle.Flag = CreateDrawingObject("Text")
	SetTextDefaults(Bundle.Info, true)
	SetTextDefaults(Bundle.Flag, false)
	SetDrawingProperty(Bundle.Flag, "Text", "TARGET")
	SetDrawingProperty(Bundle.Flag, "Color", Color3.fromRGB(149, 192, 33))
	SetDrawingProperty(Bundle.Flag, "Transparency", 1)

	Bundle.HealthBackground = CreateDrawingObject("Square")
	Bundle.HealthBar = CreateDrawingObject("Square")
	SetDrawingProperty(Bundle.HealthBackground, "Filled", true)
	SetDrawingProperty(Bundle.HealthBackground, "Color", Color3.fromRGB(0, 0, 0))
	SetDrawingProperty(Bundle.HealthBackground, "Transparency", 0.9)
	SetDrawingProperty(Bundle.HealthBackground, "Visible", false)
	SetDrawingProperty(Bundle.HealthBackground, "ZIndex", 10)

	SetDrawingProperty(Bundle.HealthBar, "Filled", true)
	SetDrawingProperty(Bundle.HealthBar, "Transparency", 1)
	SetDrawingProperty(Bundle.HealthBar, "Visible", false)
	SetDrawingProperty(Bundle.HealthBar, "ZIndex", 11)

	Bundle.Chams = CreateDrawingObject("Square")
	SetDrawingProperty(Bundle.Chams, "Filled", true)
	SetDrawingProperty(Bundle.Chams, "Visible", false)
	SetDrawingProperty(Bundle.Chams, "ZIndex", 5)

	Bundle.SnaplineOutline = CreateDrawingObject("Line")
	Bundle.Snapline = CreateDrawingObject("Line")
	SetDrawingProperty(Bundle.SnaplineOutline, "Thickness", 3)
	SetDrawingProperty(Bundle.SnaplineOutline, "Color", Color3.fromRGB(0, 0, 0))
	SetDrawingProperty(Bundle.SnaplineOutline, "Visible", false)
	SetDrawingProperty(Bundle.SnaplineOutline, "ZIndex", 9)

	SetDrawingProperty(Bundle.Snapline, "Thickness", 1)
	SetDrawingProperty(Bundle.Snapline, "Visible", false)
	SetDrawingProperty(Bundle.Snapline, "ZIndex", 10)

	if #Bundle.Box == 0 and not Bundle.Name and not Bundle.Chams then
		assert(false, "Matcha rejected Line, Text, and Square drawings")
	end

	Bundle.IsVisible = false
	return Bundle
end

local function HideEspBundle(Bundle)
	if not Bundle or not Bundle.IsVisible then
		return
	end

	if Bundle.Chams then
		Bundle.Chams.Visible = false
	end
	for _, Line in Bundle.BoxOutline do
		Line.Visible = false
	end
	for _, Line in Bundle.Box do
		Line.Visible = false
	end
	if Bundle.HealthBackground then
		Bundle.HealthBackground.Visible = false
	end
	if Bundle.HealthBar then
		Bundle.HealthBar.Visible = false
	end
	if Bundle.Name then
		Bundle.Name.Visible = false
	end
	if Bundle.Info then
		Bundle.Info.Visible = false
	end
	if Bundle.Flag then
		Bundle.Flag.Visible = false
	end
	if Bundle.SnaplineOutline then
		Bundle.SnaplineOutline.Visible = false
	end
	if Bundle.Snapline then
		Bundle.Snapline.Visible = false
	end
	Bundle.IsVisible = false
end

local function HideAllEspBundles()
	for _, Bundle in EspBundles do
		HideEspBundle(Bundle)
	end
end

local function SetEspBoxLines(Lines, TopLeft, TopRight, BottomRight, BottomLeft, Color, Alpha, UpdateStyle)
	if not Lines or #Lines < 4 then
		return false
	end

	Lines[1].From = TopLeft
	Lines[1].To = TopRight
	Lines[2].From = TopRight
	Lines[2].To = BottomRight
	Lines[3].From = BottomRight
	Lines[3].To = BottomLeft
	Lines[4].From = BottomLeft
	Lines[4].To = TopLeft

	for _, Line in Lines do
		if UpdateStyle then
			Line.Color = Color
			Line.Transparency = Alpha
		end
		Line.Visible = true
	end
	return true
end

local function GetEspBundle(Player)
	local PlayerIdentity = GetPlayerIdentity(Player)
	local Bundle = EspBundles[PlayerIdentity]
	if not Bundle then
		if EspRendererFailed then
			return nil
		end

		local Success, Result = pcall(CreateEspBundle)
		if not Success then
			EspRendererFailed = true
			ReportEspError("drawing creation failed", Result)
			return nil
		end

		Bundle = Result
		Bundle.PlayerIdentity = PlayerIdentity
		EspBundles[PlayerIdentity] = Bundle
	end
	return Bundle
end

local function IsEspTeammate(Player)
	if not Flags.EspTeamCheck then
		return false
	end

	local Success, Result = pcall(function()
		return Player.Team ~= nil and Player.Team == LocalPlayer.Team
	end)
	return Success and Result
end

local function GetHeldWeaponName(Character, Player)
	for _, Source in { Character, Player } do
		for _, AttributeName in { "EquippedWeapon", "WeaponName", "CurrentWeapon", "Weapon" } do
			local Value = GetAttributeSafe(Source, AttributeName)
			if type(Value) == "string" and Value ~= "" then
				return Value
			end
		end
	end

	local ChildrenSuccess, Children = pcall(function()
		return Character:GetChildren()
	end)
	if not ChildrenSuccess or not Children then
		return nil
	end

	for _, Child in Children do
		local ClassName
		pcall(function()
			ClassName = Child.ClassName
		end)
		if ClassName == "Tool" then
			return Child.Name
		end
	end

	for _, ValueName in { "EquippedWeapon", "WeaponName", "CurrentWeapon" } do
		local ValueObject = FindChildSafe(Character, ValueName, true)
		local Value = GetPropertySafe(ValueObject, "Value")
		if type(Value) == "string" and Value ~= "" then
			return Value
		end
	end
	return nil
end

local function GetCachedWeaponName(Character, Player, Now)
	Now = Now or Clock()
	local CharacterIdentity = GetInstanceIdentity(Character)
	local Cached = EspWeaponCache[CharacterIdentity]
	if Cached and Now < Cached.ExpiresAt then
		return Cached.Name
	end

	local WeaponName = GetHeldWeaponName(Character, Player)
	EspWeaponCache[CharacterIdentity] = {
		Name = WeaponName,
		ExpiresAt = Now + 0.25,
	}
	return WeaponName
end

local function GetPlayerCharacter(Player, Now)
	return ResolvePlayerCharacter(Player, Now)
end

local function ResolveEspCharacter(Character, Now)
	return ResolveCharacterModel(Character, Now)
end

local function GetEspTarget(Player, Now)
	if not Player then
		return nil
	end

	local PlayerIdentity = GetPlayerIdentity(Player)
	if PlayerIdentity == LocalPlayerIdentity or IsEspTeammate(Player) then
		return nil
	end

	Now = Now or Clock()
	local Character = GetPlayerCharacter(Player, Now)
	if not Character then
		EspTargetCache[PlayerIdentity] = nil
		return nil
	end

	local CharacterIdentity = GetInstanceIdentity(Character)
	local Cached = EspTargetCache[PlayerIdentity]
	local Head
	local RootPart

	if Cached and Cached.CharacterIdentity == CharacterIdentity and Now < Cached.ExpiresAt then
		Head = Cached.Head
		RootPart = Cached.RootPart
	else
		local ModelInfo = ResolveEspCharacter(Character, Now)
		if not ModelInfo then
			EspTargetCache[PlayerIdentity] = nil
			return nil
		end
		Head = ModelInfo.Head
		RootPart = ModelInfo.RootPart
		local DisplayName = Player.Name
		pcall(function()
			if Player.DisplayName and Player.DisplayName ~= "" then
				DisplayName = Player.DisplayName
			end
		end)
		Cached = {
			Player = Player,
			Character = Character,
			CharacterIdentity = CharacterIdentity,
			Humanoid = ModelInfo.Humanoid,
			ControllerManager = ModelInfo.ControllerManager,
			Head = Head,
			RootPart = RootPart,
			UpperTorso = ModelInfo.UpperTorso,
			BaseParts = ModelInfo.BaseParts,
			HealthValue = ModelInfo.HealthValue,
			MaxHealthValue = ModelInfo.MaxHealthValue,
			AliveValue = ModelInfo.AliveValue,
			DeadValue = ModelInfo.DeadValue,
			DisplayName = DisplayName,
			ExpiresAt = Now + 0.75,
		}
		EspTargetCache[PlayerIdentity] = Cached
	end

	if not RootPart or not Head then
		EspTargetCache[PlayerIdentity] = nil
		return nil
	end
	if not GetPartPosition(Head) or not GetPartPosition(RootPart) then
		EspTargetCache[PlayerIdentity] = nil
		return nil
	end

	local Health, MaxHealth = GetCharacterHealth(Player, Cached)
	if Health <= 0 then
		return nil
	end

	Cached.Player = Player
	Cached.Character = Character
	Cached.Head = Head
	Cached.RootPart = RootPart
	Cached.Health = Health
	Cached.MaxHealth = math.max(MaxHealth or 100, 1)
	Cached.WeaponName = Flags.EspWeapon and GetCachedWeaponName(Character, Player, Now) or nil
	Cached.DisplayName = Cached.DisplayName or Player.Name
	return Cached
end

local function GetEspBox(Target, RootPosition)
	local HeadPosition = GetPartPosition(Target.Head)
	if not HeadPosition or not RootPosition then
		return nil
	end

	local HeadScreen, HeadVisible = ProjectToScreen(HeadPosition)
	local RootScreen, RootVisible = ProjectToScreen(RootPosition)
	if not RootVisible then
		return nil
	end
	if not HeadVisible then
		HeadScreen = RootScreen
	end

	local BodySpan = math.abs(RootScreen.Y - HeadScreen.Y)
	local Height = math.max(BodySpan * 3.15, 18)
	local Width = Height * 0.52
	local CenterX = (HeadScreen.X + RootScreen.X) * 0.5
	local TopY
	if BodySpan >= 2 then
		TopY = math.min(HeadScreen.Y, RootScreen.Y) - BodySpan * 0.55
	else
		TopY = RootScreen.Y - Height * 0.55
	end

	return CenterX - Width * 0.5, TopY, Width, Height
end

local function UpdateEspBundle(Bundle, Target, Origin, SnaplineFrom, Now, MaxDistanceSquared)
	local TargetPosition = GetPartPosition(Target.RootPart)
	if not TargetPosition then
		return false
	end

	if not Origin then
		return false
	end

	local DistanceOffset = Origin - TargetPosition
	local DistanceSquared = LengthSquared(DistanceOffset)
	if DistanceSquared > MaxDistanceSquared then
		return false
	end

	local X, Y, Width, Height = GetEspBox(Target, TargetPosition)
	if not X then
		return false
	end

	-- Mark first so a protected per-player failure can still hide partial drawing updates.
	Bundle.IsVisible = true
	local CenterX = X + Width * 0.5
	local TextStyleChanged = Bundle.TextColor ~= Flags.EspTextColor
		or Bundle.TextAlpha ~= Flags.EspTextAlpha
	if TextStyleChanged then
		if Bundle.Name then
			Bundle.Name.Color = Flags.EspTextColor
			Bundle.Name.Transparency = Flags.EspTextAlpha
		end
		if Bundle.Info then
			Bundle.Info.Color = Flags.EspTextColor
			Bundle.Info.Transparency = Flags.EspTextAlpha
		end
		Bundle.TextColor = Flags.EspTextColor
		Bundle.TextAlpha = Flags.EspTextAlpha
	end

	if Flags.EspChams and Bundle.Chams then
		Bundle.Chams.Position = Vector2.new(X + 2, Y + 2)
		Bundle.Chams.Size = Vector2.new(math.max(Width - 4, 1), math.max(Height - 4, 1))
		if Bundle.ChamsColor ~= Flags.EspChamsColor or Bundle.ChamsAlpha ~= Flags.EspChamsAlpha then
			Bundle.Chams.Color = Flags.EspChamsColor
			Bundle.Chams.Transparency = Flags.EspChamsAlpha
			Bundle.ChamsColor = Flags.EspChamsColor
			Bundle.ChamsAlpha = Flags.EspChamsAlpha
		end
		Bundle.Chams.Visible = true
	elseif Bundle.Chams then
		Bundle.Chams.Visible = false
	end

	if Flags.EspBox then
		local TopLeft = Vector2.new(X, Y)
		local TopRight = Vector2.new(X + Width, Y)
		local BottomRight = Vector2.new(X + Width, Y + Height)
		local BottomLeft = Vector2.new(X, Y + Height)
		local OutlineStyleChanged = Bundle.BoxOutlineAlpha ~= Flags.EspBoxAlpha
		local BoxStyleChanged = Bundle.BoxColor ~= Flags.EspBoxColor or Bundle.BoxAlpha ~= Flags.EspBoxAlpha

		SetEspBoxLines(
			Bundle.BoxOutline,
			TopLeft,
			TopRight,
			BottomRight,
			BottomLeft,
			EspOutlineColor,
			Flags.EspBoxAlpha,
			OutlineStyleChanged
		)
		SetEspBoxLines(
			Bundle.Box,
			TopLeft,
			TopRight,
			BottomRight,
			BottomLeft,
			Flags.EspBoxColor,
			Flags.EspBoxAlpha,
			BoxStyleChanged
		)
		Bundle.BoxOutlineAlpha = Flags.EspBoxAlpha
		Bundle.BoxColor = Flags.EspBoxColor
		Bundle.BoxAlpha = Flags.EspBoxAlpha
	else
		for _, Line in Bundle.BoxOutline do
			Line.Visible = false
		end
		for _, Line in Bundle.Box do
			Line.Visible = false
		end
	end

	if Flags.EspHealth and Bundle.HealthBackground and Bundle.HealthBar then
		local HealthRatio = Clamp(Target.Health / Target.MaxHealth, 0, 1)
		local BarHeight = math.max(math.floor((Height - 2) * HealthRatio), 1)
		Bundle.HealthBackground.Position = Vector2.new(X - 6, Y - 1)
		Bundle.HealthBackground.Size = Vector2.new(4, Height + 2)
		Bundle.HealthBackground.Visible = true

		Bundle.HealthBar.Position = Vector2.new(X - 5, Y + Height - 1 - BarHeight)
		Bundle.HealthBar.Size = Vector2.new(2, BarHeight)
		if Bundle.HealthRatio ~= HealthRatio then
			Bundle.HealthBar.Color = Color3.new(1 - HealthRatio, HealthRatio, 0)
			Bundle.HealthRatio = HealthRatio
		end
		Bundle.HealthBar.Visible = true
	else
		if Bundle.HealthBackground then
			Bundle.HealthBackground.Visible = false
		end
		if Bundle.HealthBar then
			Bundle.HealthBar.Visible = false
		end
	end

	if Flags.EspName and Bundle.Name then
		if Bundle.NameText ~= Target.DisplayName then
			Bundle.Name.Text = Target.DisplayName
			Bundle.NameText = Target.DisplayName
		end
		Bundle.Name.Position = Vector2.new(CenterX, Y - 15)
		Bundle.Name.Visible = true
	elseif Bundle.Name then
		Bundle.Name.Visible = false
	end

	local InfoText
	if Flags.EspDistance then
		local Distance = math.sqrt(DistanceSquared)
		InfoText = "[" .. tostring(math.floor(Distance + 0.5)) .. "u]"
	end
	if Flags.EspWeapon then
		local WeaponName = Target.WeaponName
		if WeaponName then
			InfoText = InfoText and (InfoText .. "  " .. WeaponName) or WeaponName
		end
	end
	if InfoText and Bundle.Info then
		if Bundle.InfoText ~= InfoText then
			Bundle.Info.Text = InfoText
			Bundle.InfoText = InfoText
		end
		Bundle.Info.Position = Vector2.new(CenterX, Y + Height + 2)
		Bundle.Info.Visible = true
	elseif Bundle.Info then
		Bundle.Info.Visible = false
	end

	if Bundle.Flag and Flags.LockedPlayerName == Target.Player.Name then
		Bundle.Flag.Position = Vector2.new(X + Width + 4, Y)
		Bundle.Flag.Visible = true
	elseif Bundle.Flag then
		Bundle.Flag.Visible = false
	end

	if Flags.EspSnapline and Bundle.SnaplineOutline and Bundle.Snapline then
		if SnaplineFrom then
			local To = Vector2.new(CenterX, Y + Height)
			Bundle.SnaplineOutline.From = SnaplineFrom
			Bundle.SnaplineOutline.To = To
			if Bundle.SnaplineAlpha ~= Flags.EspSnaplineAlpha then
				Bundle.SnaplineOutline.Transparency = Flags.EspSnaplineAlpha
			end
			Bundle.SnaplineOutline.Visible = true

			Bundle.Snapline.From = SnaplineFrom
			Bundle.Snapline.To = To
			if Bundle.SnaplineColor ~= Flags.EspSnaplineColor or Bundle.SnaplineAlpha ~= Flags.EspSnaplineAlpha then
				Bundle.Snapline.Color = Flags.EspSnaplineColor
				Bundle.Snapline.Transparency = Flags.EspSnaplineAlpha
				Bundle.SnaplineColor = Flags.EspSnaplineColor
			end
			Bundle.SnaplineAlpha = Flags.EspSnaplineAlpha
			Bundle.Snapline.Visible = true
		else
			Bundle.SnaplineOutline.Visible = false
			Bundle.Snapline.Visible = false
		end
	else
		if Bundle.SnaplineOutline then
			Bundle.SnaplineOutline.Visible = false
		end
		if Bundle.Snapline then
			Bundle.Snapline.Visible = false
		end
	end

	Bundle.IsVisible = true
	Bundle.LastDrawnAt = Now
	return true
end

local function UpdateEspFrame(Now)
	if not Flags.Running or not Flags.EspEnabled then
		if EspWasEnabled then
			HideAllEspBundles()
			EspWasEnabled = false
		end
		if EspStatus.Text ~= "off" then
			EspStatus.Text = "off"
		end
		return
	end
	EspWasEnabled = true

	if EspRendererFailed then
		HideAllEspBundles()
		if not EspStatus.LastError then
			EspStatus.Text = "renderer unavailable"
		end
		return
	end

	Now = Now or Clock()
	local Camera = Workspace.CurrentCamera
	if not Camera then
		HideAllEspBundles()
		EspStatus.Text = "waiting for camera"
		return
	end

	local Origin = GetPartPosition(GetLocalRoot())
	if not Origin then
		pcall(function()
			Origin = Camera.Position
		end)
	end
	if not Origin then
		HideAllEspBundles()
		EspStatus.Text = "waiting for position"
		return
	end

	local SnaplineFrom
	if Flags.EspSnapline then
		local ViewportSize
		pcall(function()
			ViewportSize = Camera.ViewportSize
		end)
		if ViewportSize then
			SnaplineFrom = Vector2.new(ViewportSize.X * 0.5, ViewportSize.Y)
		end
	end

	local PlayerCount = 0
	local DrawnCount = 0
	local MaxDistanceSquared = Flags.EspMaxDistance * Flags.EspMaxDistance
	EspFrameId = EspFrameId + 1
	local CurrentFrameId = EspFrameId

	for _, Player in CachedPlayers do
		if GetPlayerIdentity(Player) ~= LocalPlayerIdentity then
			PlayerCount = PlayerCount + 1
		end

		local Bundle
		local Success, WasDrawn = pcall(function()
			local Target = GetEspTarget(Player, Now)
			if Target then
				Bundle = GetEspBundle(Player)
				if Bundle then
					return UpdateEspBundle(Bundle, Target, Origin, SnaplineFrom, Now, MaxDistanceSquared)
				end
			end
			return false
		end)
		if not Success and not EspErrorReported then
			ReportEspError("player update failed", WasDrawn)
		elseif Success and WasDrawn then
			DrawnCount = DrawnCount + 1
			Bundle.ActiveFrame = CurrentFrameId
		end
	end

	for _, Bundle in EspBundles do
		if
			Bundle.ActiveFrame ~= CurrentFrameId
			and (not Bundle.LastDrawnAt or Now - Bundle.LastDrawnAt > 0.08)
		then
			HideEspBundle(Bundle)
		end
	end

	if not EspStatus.LastError then
		EspStatus.Text = tostring(DrawnCount) .. "/" .. tostring(PlayerCount) .. " drawn"
	end
end

local function UpdateEspLoop(DeltaTime)
	if not Flags.Running then
		return
	end

	if not Flags.EspEnabled then
		EspUpdateAccumulator = 0
		if not EspWasEnabled then
			return
		end
	else
		local FrameTime = Clamp(DeltaTime or ESP_UPDATE_INTERVAL, 0, 0.1)
		EspUpdateAccumulator = EspUpdateAccumulator + FrameTime
		if EspWasEnabled and EspUpdateAccumulator < ESP_UPDATE_INTERVAL then
			return
		end
		EspUpdateAccumulator = EspUpdateAccumulator % ESP_UPDATE_INTERVAL
	end

	local Success, ErrorMessage = pcall(UpdateEspFrame, Clock())
	if not Success then
		ReportEspError("ESP frame failed", ErrorMessage)
	end
end

local FovCircleOutline = CreateDrawingObject("Circle")
if FovCircleOutline then
	SetDrawingProperty(FovCircleOutline, "Thickness", 3)
	SetDrawingProperty(FovCircleOutline, "NumSides", 64)
	SetDrawingProperty(FovCircleOutline, "Color", Color3.fromRGB(0, 0, 0))
	SetDrawingProperty(FovCircleOutline, "Visible", false)
end

local FovCircle = CreateDrawingObject("Circle")
if FovCircle then
	SetDrawingProperty(FovCircle, "Thickness", 1)
	SetDrawingProperty(FovCircle, "NumSides", 64)
	SetDrawingProperty(FovCircle, "Visible", false)
	SetDrawingProperty(FovCircle, "ZIndex", 5)
end
local CanDrawFov = FovCircleOutline ~= nil and FovCircle ~= nil

local SilentStatusUpdatedAt = -math.huge
local FovWasVisible = false
local LastFovRadius
local LastFovColor
local LastFovAlpha

local function UpdateFovLoop()
	if not Flags.Running then
		return
	end

	local ShowAimFov = CanDrawFov and Flags.DrawFov
	local ShowSilentFov = CanDrawFov and Flags.DrawFov and Flags.SilentAim and Flags.SilentFovCheck
	local ShowFov = ShowAimFov or ShowSilentFov
	local DisplayFovRadius = 0
	if ShowAimFov then
		DisplayFovRadius = math.max(DisplayFovRadius, Flags.FovRadius)
	end
	if ShowSilentFov then
		DisplayFovRadius = math.max(DisplayFovRadius, Flags.SilentFovRadius)
	end

	local MousePosition
	if ShowFov then
		MousePosition = GetMousePosition()
		FovCircleOutline.Position = MousePosition
		FovCircle.Position = MousePosition

		if LastFovRadius ~= DisplayFovRadius then
			FovCircleOutline.Radius = DisplayFovRadius + 1
			FovCircle.Radius = DisplayFovRadius
			LastFovRadius = DisplayFovRadius
		end
		if LastFovColor ~= Flags.FovColor then
			FovCircle.Color = Flags.FovColor
			LastFovColor = Flags.FovColor
		end
		if LastFovAlpha ~= Flags.FovAlpha then
			FovCircleOutline.Transparency = Flags.FovAlpha
			FovCircle.Transparency = Flags.FovAlpha
			LastFovAlpha = Flags.FovAlpha
		end
	end

	if CanDrawFov and FovWasVisible ~= ShowFov then
		FovCircleOutline.Visible = ShowFov
		FovCircle.Visible = ShowFov
		FovWasVisible = ShowFov
	end

	local Now = Clock()
	if Flags.SilentAim and Now - SilentStatusUpdatedAt >= 0.1 then
		SilentStatusUpdatedAt = Now
		local Target, ScreenDistance, WorldDistance = FindSilentTarget(MousePosition)
		UpdateSilentTargetStatus(Target, ScreenDistance, WorldDistance)
	elseif not Flags.SilentAim and SilentAimStatus.Text ~= "inactive" then
		SilentAimStatus.Text = "inactive"
	end
end

local function UpdateAimLoop(DeltaTime)
	if not Flags.Running then
		return
	end

	if not Flags.Aimbot or not Flags.AimbotActive then
		if LockedPlayer or Flags.LockedPlayerName or SmoothedAimPosition then
			ClearLock()
		end
		return
	end

	local Camera = Workspace.CurrentCamera
	if not Camera then
		ClearAimSmoothing()
		return
	end

	local MousePosition = GetMousePosition()
	local Target
	local HasStickyLock = Flags.StickyAim and (LockedPlayer ~= nil or Flags.LockedPlayerName ~= nil)
	if HasStickyLock then
		Target = GetLockedTarget(MousePosition)
		if not Target then
			ClearLock()
			return
		end
	else
		Target = FindClosestTarget(nil, MousePosition)
		if Target and Flags.StickyAim then
			LockedPlayer = Target.Player
			Flags.LockedPlayerName = Target.Player.Name
		end
	end

	if not Target then
		ClearAimSmoothing()
		return
	end

	local CameraPosition = Camera.Position
	local AimPosition = PredictTargetPosition(Target, CameraPosition)
	if not AimPosition then
		ClearAimSmoothing()
		return
	end

	local TargetName = Target.Player.Name
	local Smoothness = Clamp(Flags.AimSmoothness or 0, 0, 100)
	local LookPosition = AimPosition
	if Smoothness > 0 then
		if SmoothedAimPosition and SmoothedAimTargetName == TargetName then
			if CachedAimSmoothness ~= Smoothness then
				CachedAimSmoothness = Smoothness
				CachedAimResponseSpeed = 28 - (Smoothness * 0.26)
			end
			local FrameTime = Clamp(DeltaTime or (1 / 60), 0, 1 / 15)
			local Alpha = Clamp(1 - math.exp(-CachedAimResponseSpeed * FrameTime), 0.01, 1)
			SmoothedAimPosition = SmoothedAimPosition + (AimPosition - SmoothedAimPosition) * Alpha
		else
			SmoothedAimPosition = AimPosition
		end
		SmoothedAimTargetName = TargetName
		LookPosition = SmoothedAimPosition
	else
		SmoothedAimPosition = AimPosition
		SmoothedAimTargetName = TargetName
	end

	local AimSuccess = pcall(function()
		Camera.lookAt(CameraPosition, LookPosition)
	end)
	if not AimSuccess then
		ClearAimSmoothing()
	end
end

task.spawn(function()
	local PreviousFrame = Clock()
	while Flags.Running do
		local Now = Clock()
		local DeltaTime = Clamp(Now - PreviousFrame, 0, 0.1)
		PreviousFrame = Now
		pcall(UpdateEspLoop, DeltaTime)
		pcall(UpdateFovLoop)
		pcall(UpdateAimLoop, DeltaTime)
		task.wait(1 / 120)
	end
end)

Environment.SilentAim = SilentAim
Environment.UnloadDesertStormAim = Runtime.Unload
Environment.UnloadGlobalAnarchyAim = Runtime.Unload
Environment.__MatchaAimRuntime = Runtime
