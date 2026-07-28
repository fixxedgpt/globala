local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local LocalPlayer = Players.LocalPlayer

if not LocalPlayer then
	warn("LocalPlayer is unavailable; aborting cleanly.")
	return
end

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
local EspStatus = {
	Text = "off",
	LastError = nil,
}
local SilentAimStatus = {
	Text = "inactive",
}

local Runtime = {
	AimStatus = "ready",
}

local function TrackConnection(Connection)
	Connections[#Connections + 1] = Connection
	return Connection
end

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
	end
end

local InitializationComplete = false
Environment.__MatchaAimRuntime = Runtime
task.delay(4, function()
	if InitializationComplete or not Flags.Running then
		return
	end
	warn("Initialization did not complete; releasing the partial UI.")
	Runtime.Unload()
end)

local function Clamp(Value, Minimum, Maximum)
	if Value < Minimum then
		return Minimum
	end
	if Value > Maximum then
		return Maximum
	end
	return Value
end

local CachedPingSeconds = 0
local PingUpdatedAt = -math.huge

local function GetPingSeconds()
	local Now = tick()
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

local function GetPartPosition(Part)
	local Success, Position = pcall(function()
		return Part and Part.Position
	end)
	return Success and Position or nil
end

local function SafeFindFirstChild(Parent, Name)
	local Success, Child = pcall(function()
		return Parent and Parent:FindFirstChild(Name)
	end)
	return Success and Child or nil
end

Runtime.PlayerModels = {}

Runtime.MapModelCandidate = function(Candidate)
	if not Candidate or Candidate == Workspace then
		return
	end

	local IsModel = false
	pcall(function()
		IsModel = Candidate:IsA("Model")
	end)
	if not IsModel then
		pcall(function()
			Candidate = Candidate.Parent
		end)
	end
	if not Candidate or Candidate == Workspace then
		return
	end

	Runtime.ModelCandidateSet = Runtime.ModelCandidateSet or {}
	if Runtime.ModelCandidateSet[Candidate] then
		return
	end
	Runtime.ModelCandidateSet[Candidate] = true
	Runtime.ModelCandidates[#Runtime.ModelCandidates + 1] = Candidate
	Runtime.ControllerRigCount = #Runtime.ModelCandidates

	local Owner
	pcall(function()
		Owner = Players:GetPlayerFromCharacter(Candidate)
	end)
	if Owner then
		Runtime.PlayerModels[Owner] = Candidate
		Runtime.ModelClaims[Candidate] = true
		return
	end

	local CameraSubject
	pcall(function()
		CameraSubject = Workspace.CurrentCamera and Workspace.CurrentCamera.CameraSubject
	end)
	if CameraSubject then
		local IsLocalCharacter = CameraSubject == Candidate
		pcall(function()
			IsLocalCharacter = IsLocalCharacter or CameraSubject:IsDescendantOf(Candidate)
		end)
		if IsLocalCharacter then
			Runtime.PlayerModels[LocalPlayer] = Candidate
			Runtime.ModelClaims[Candidate] = true
			return
		end
	end

	local CandidateName = ""
	local OwnerName
	local OwnerId
	pcall(function()
		CandidateName = string.lower(Candidate.Name)
		OwnerName = Candidate:GetAttribute("PlayerName")
			or Candidate:GetAttribute("OwnerName")
			or Candidate:GetAttribute("Username")
		OwnerId = Candidate:GetAttribute("UserId")
			or Candidate:GetAttribute("PlayerUserId")
			or Candidate:GetAttribute("OwnerUserId")
	end)
	for _, CandidatePlayer in Players:GetPlayers() do
		local PlayerName
		local UserId
		pcall(function()
			PlayerName = CandidatePlayer.Name
			UserId = CandidatePlayer.UserId
		end)
		if
			PlayerName
			and (
				OwnerName == PlayerName
				or string.find(CandidateName, string.lower(PlayerName), 1, true)
				or (UserId and tostring(OwnerId) == tostring(UserId))
				or (UserId and string.find(CandidateName, tostring(UserId), 1, true))
			)
		then
			Runtime.PlayerModels[CandidatePlayer] = Candidate
			Runtime.ModelClaims[Candidate] = true
			return
		end
	end
end

Runtime.ProcessModelScan = function()
	if not Flags.Running or not Runtime.ModelScanActive then
		Runtime.ModelScanActive = false
		return
	end

	local Queue = Runtime.ModelScanQueue
	local Index = Runtime.ModelScanIndex
	local LastIndex = math.min(Index + 47, #Queue)
	while Index <= LastIndex do
		local Instance = Queue[Index]
		Index = Index + 1

		local ClassName
		local InstanceName
		local Parent
		pcall(function()
			ClassName = Instance.ClassName
			InstanceName = Instance.Name
			Parent = Instance.Parent
		end)
		if ClassName == "ControllerManager" then
			Runtime.MapModelCandidate(Parent)
		elseif InstanceName then
			local LowerName = string.lower(InstanceName)
			if LowerName == "characterblock" or LowerName == "characterroot" then
				Runtime.MapModelCandidate(Parent)
			end
		end

		local Children
		pcall(function()
			Children = Instance:GetChildren()
		end)
		for _, Child in Children or {} do
			Queue[#Queue + 1] = Child
		end
	end
	Runtime.ModelScanIndex = Index

	if Index <= #Queue then
		task.delay(0.01, Runtime.ProcessModelScan)
		return
	end

	for _, KnownPlayer in Players:GetPlayers() do
		local KnownCharacter
		pcall(function()
			KnownCharacter = KnownPlayer.Character
		end)
		if KnownCharacter then
			Runtime.PlayerModels[KnownPlayer] = KnownCharacter
			Runtime.ModelClaims[KnownCharacter] = true
		end
	end

	local CandidateIndex = 1
	for _, CandidatePlayer in Players:GetPlayers() do
		if not Runtime.PlayerModels[CandidatePlayer] then
			while
				Runtime.ModelCandidates[CandidateIndex]
				and Runtime.ModelClaims[Runtime.ModelCandidates[CandidateIndex]]
			do
				CandidateIndex = CandidateIndex + 1
			end
			local Candidate = Runtime.ModelCandidates[CandidateIndex]
			if Candidate then
				Runtime.PlayerModels[CandidatePlayer] = Candidate
				Runtime.ModelClaims[Candidate] = true
				CandidateIndex = CandidateIndex + 1
			end
		end
	end

	Runtime.ModelScanQueue = nil
	Runtime.ModelScanActive = false
	Runtime.ModelScanFinishedAt = tick()
	Runtime.AimStatus = "models ready | " .. tostring(Runtime.ControllerRigCount or 0) .. " rigs"
end

Runtime.RequestModelScan = function()
	if Runtime.ModelScanActive or tick() - (Runtime.ModelScanFinishedAt or -math.huge) < 2 then
		return
	end
	Runtime.ModelCandidates = {}
	Runtime.ModelCandidateSet = {}
	Runtime.ModelClaims = {}
	Runtime.ControllerRigCount = 0
	Runtime.ModelScanQueue = { Workspace }
	Runtime.ModelScanIndex = 1
	Runtime.ModelScanActive = true
	Runtime.AimStatus = "scanning models..."
	task.delay(0, Runtime.ProcessModelScan)
end

local function GetPlayerCharacter(Player)
	local Character
	pcall(function()
		Character = Player.Character
	end)
	if Character then
		Runtime.PlayerModels[Player] = Character
		return Character
	end

	local CachedCharacter = Runtime.PlayerModels[Player]
	if CachedCharacter then
		return CachedCharacter
	end

	Runtime.PlayerModelMissAt = Runtime.PlayerModelMissAt or {}
	local Now = tick()
	if Now - (Runtime.PlayerModelMissAt[Player] or -math.huge) < 0.25 then
		return nil
	end

	local PlayerName
	local UserId
	pcall(function()
		PlayerName = Player.Name
		UserId = Player.UserId
	end)
	if not PlayerName then
		return nil
	end

	Character = SafeFindFirstChild(Workspace, PlayerName)
	UserId = UserId and tostring(UserId) or nil
	for _, ContainerName in { "Characters", "PlayerCharacters", "PlayerModels", "Actors", "Entities", "Alive" } do
		if Character then
			break
		end
		local Container = SafeFindFirstChild(Workspace, ContainerName)
		if Container then
			Character = SafeFindFirstChild(Container, PlayerName)
			if not Character and UserId then
				Character = SafeFindFirstChild(Container, UserId)
			end
		end
	end

	if Character then
		Runtime.PlayerModels[Player] = Character
		Runtime.PlayerModelMissAt[Player] = nil
		return Character
	end

	Runtime.PlayerModelMissAt[Player] = Now
	Runtime.RequestModelScan()
	return Runtime.PlayerModels[Player]
end

local function ResolveEspCharacter(Character)
	if not Character then
		return nil, nil, nil, nil
	end

	Runtime.CharacterParts = Runtime.CharacterParts or {}
	local Now = tick()
	local Cached = Runtime.CharacterParts[Character]
	if Cached and Now < Cached.ExpiresAt and GetPartPosition(Cached.RootPart) then
		return Cached.Humanoid, Cached.Head, Cached.RootPart, Cached.UpperTorso
	end

	local Humanoid = SafeFindFirstChild(Character, "Humanoid")
	local Head = SafeFindFirstChild(Character, "Head")
	local UpperTorso = SafeFindFirstChild(Character, "UpperTorso") or SafeFindFirstChild(Character, "Torso")
	local RootPart = SafeFindFirstChild(Character, "HumanoidRootPart")
		or SafeFindFirstChild(Character, "RootPart")
		or SafeFindFirstChild(Character, "CharacterBlock")
	local ControllerManager
	local FirstPart
	local HighestPart = Head
	local HighestY = -math.huge

	local Descendants
	pcall(function()
		Descendants = Character:GetDescendants()
	end)
	for _, Descendant in Descendants or {} do
		local ClassName
		pcall(function()
			ClassName = Descendant.ClassName
		end)

		if not ControllerManager and ClassName == "ControllerManager" then
			ControllerManager = Descendant
		end

		local IsBasePart = false
		pcall(function()
			IsBasePart = Descendant:IsA("BasePart")
		end)
		if
			not IsBasePart
			and (
				ClassName == "Part"
				or ClassName == "MeshPart"
				or ClassName == "UnionOperation"
				or ClassName == "TrussPart"
				or ClassName == "Seat"
				or ClassName == "VehicleSeat"
			)
		then
			IsBasePart = true
		end
		if IsBasePart then
			FirstPart = FirstPart or Descendant
			local Name = string.lower(Descendant.Name)
			if not Head and (Name == "head" or Name == "headhitbox" or Name == "skull") then
				Head = Descendant
			elseif not RootPart
				and (
					Name == "root"
					or Name == "rootpart"
					or Name == "characterroot"
					or Name == "characterblock"
					or Name == "collision"
					or Name == "collider"
				)
			then
				RootPart = Descendant
			end
			if
				not UpperTorso
				and (Name == "uppertorso" or Name == "torso" or Name == "body" or Name == "chest")
			then
				UpperTorso = Descendant
			end
			local Position = GetPartPosition(Descendant)
			if Position and Position.Y > HighestY then
				HighestY = Position.Y
				HighestPart = Descendant
			end
		elseif not Humanoid then
			pcall(function()
				if Descendant:IsA("Humanoid") then
					Humanoid = Descendant
				end
			end)
		end
	end

	if not ControllerManager then
		pcall(function()
			ControllerManager = Character:FindFirstChildWhichIsA("ControllerManager")
		end)
	end
	if ControllerManager then
		local ControllerRoot
		pcall(function()
			ControllerRoot = ControllerManager.RootPart
		end)
		RootPart = ControllerRoot or RootPart
		Runtime.ControllerResolverSeen = true
	end

	if not RootPart then
		pcall(function()
			RootPart = Character.PrimaryPart
		end)
	end
	RootPart = RootPart or UpperTorso or FirstPart
	Head = Head or HighestPart or RootPart
	UpperTorso = UpperTorso or RootPart
	Runtime.CharacterParts[Character] = {
		Humanoid = Humanoid,
		Head = Head,
		RootPart = RootPart,
		UpperTorso = UpperTorso,
		ExpiresAt = Now + 0.75,
	}
	return Humanoid, Head, RootPart, UpperTorso
end

local function GetLocalRoot()
	local Character = GetPlayerCharacter(LocalPlayer)
	local _, _, RootPart = ResolveEspCharacter(Character)
	return RootPart
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

local function ResolveTargetPart(Character, Head, RootPart, UpperTorso, MousePosition)
	if not MousePosition then
		local Mouse = LocalPlayer:GetMouse()
		MousePosition = Vector2.new(Mouse.X, Mouse.Y)
	end
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
				ConsiderPart(Character:FindFirstChild(LegPartName))
			end
		elseif PartName == "Feet" then
			for _, FootPartName in FootPartNames do
				ConsiderPart(Character:FindFirstChild(FootPartName))
			end
		elseif PartName == "Closest" then
			for _, Part in Character:GetChildren() do
				if Part:IsA("BasePart") then
					ConsiderPart(Part)
				end
			end
		end
	end

	return ClosestPart or Head or UpperTorso or RootPart
end

local function BuildTarget(Player, MousePosition)
	if not Player or Player.Name == LocalPlayer.Name or IsTeammate(Player) then
		return nil
	end

	local Character = GetPlayerCharacter(Player)
	if not Character then
		return nil
	end

	local Humanoid, Head, RootPart, UpperTorso = ResolveEspCharacter(Character)
	local Health = 100
	pcall(function()
		Health = Humanoid and Humanoid.Health or Character:GetAttribute("Health") or 100
		if Character:GetAttribute("Alive") == false or Character:GetAttribute("Dead") == true then
			Health = 0
		end
	end)
	Health = tonumber(Health) or 100
	if Health <= 0 or not RootPart or not (Head or UpperTorso) then
		return nil
	end

	local TargetPart = ResolveTargetPart(Character, Head, RootPart, UpperTorso, MousePosition)
	if not TargetPart then
		return nil
	end

	local AimOffsetY = 0
	if TargetPart == RootPart and Head == RootPart then
		pcall(function()
			AimOffsetY = math.max(RootPart.Size.Y * 0.38, 2.25)
		end)
	end

	return {
		Player = Player,
		Character = Character,
		Humanoid = Humanoid,
		Head = Head,
		RootPart = RootPart,
		UpperTorso = UpperTorso,
		TargetPart = TargetPart,
		AimOffsetY = AimOffsetY,
	}
end

local function GetLockedTarget(MousePosition)
	if LockedPlayer then
		return BuildTarget(LockedPlayer, MousePosition)
	end

	if not Flags.LockedPlayerName then
		return nil
	end
	for _, Player in Players:GetPlayers() do
		if Player.Name == Flags.LockedPlayerName then
			LockedPlayer = Player
			return BuildTarget(Player, MousePosition)
		end
	end

	return nil
end

local function FindClosestTarget(Selection, MousePosition)
	Selection = Selection or {}
	local UseFov = Selection.FovCheck
	if UseFov == nil then
		UseFov = Flags.FovCheck
	end
	local FovRadius = Selection.FovRadius or Flags.FovRadius
	local MaxDistance = Selection.MaxDistance or Flags.MaxAcquireDistance
	if not MousePosition then
		local Mouse = LocalPlayer:GetMouse()
		MousePosition = Vector2.new(Mouse.X, Mouse.Y)
	end
	local LocalRoot = GetLocalRoot()
	local LocalPosition = GetPartPosition(LocalRoot)
	local ClosestTarget
	local ClosestScreenDistanceSquared = math.huge
	local ClosestWorldDistanceSquared
	local FovRadiusSquared = FovRadius * FovRadius
	local MaxDistanceSquared = MaxDistance * MaxDistance

	for _, Player in Players:GetPlayers() do
		local Target = BuildTarget(Player, MousePosition)
		if not Target then
			continue
		end

		local TargetPosition = GetPartPosition(Target.TargetPart)
		if not TargetPosition then
			continue
		end

		local WorldDistanceSquared
		if LocalPosition then
			local Offset = LocalPosition - TargetPosition
			WorldDistanceSquared = Offset.X * Offset.X + Offset.Y * Offset.Y + Offset.Z * Offset.Z
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

	return ClosestTarget,
		ClosestTarget and math.sqrt(ClosestScreenDistanceSquared) or math.huge,
		ClosestWorldDistanceSquared and math.sqrt(ClosestWorldDistanceSquared) or nil
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
	if Target.AimOffsetY and Target.AimOffsetY > 0 then
		Position = Position + Vector3.new(0, Target.AimOffsetY, 0)
	end
	if not Flags.AutoPrediction or not Origin then
		return Position
	end

	local ProjectileSpeed = math.max(Flags.ProjectileSpeed, 1)
	local Distance = (Origin - Position).Magnitude
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

	local Target, ScreenDistance, WorldDistance = FindClosestTarget({
		FovCheck = Flags.SilentFovCheck,
		FovRadius = Flags.SilentFovRadius,
		MaxDistance = Flags.SilentMaxDistance,
	})
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

local UiStatusEntriesSupported = false

local function ReplacePlainOnce(Source, Original, Replacement)
	local StartIndex, EndIndex = string.find(Source, Original, 1, true)
	if not StartIndex then
		return Source, false
	end

	return string.sub(Source, 1, StartIndex - 1) .. Replacement .. string.sub(Source, EndIndex + 1), true
end

local function AddUiStatusEntrySupport(Source)
	local OriginalSource = Source
	local Patches = {
		{
			[=[if dU.keybind then local eh=dU.keybind;local hq=eh.listening and"..."or aq(eh.value)]=],
			[=[if dU.keybind then local eh=dU.keybind;local hq=eh.statusOnly and"ON"or eh.listening and"..."or aq(eh.value)]=],
		},
		{
			[=[local jr=D(28,bM(hq,13,aA)+14)j3=j3-jr;local js=iQ and dF(j3,iN+3,jr,20)]=],
			[=[local jr=D(28,bM(hq,13,aA)+14)j3=j3-jr;local js=not eh.statusOnly and iQ and dF(j3,iN+3,jr,20)]=],
		},
		{
			[=[key=eh and eh.value and aq(eh.value)or""]=],
			[=[key=eh and eh.statusOnly and"ON"or eh and eh.value and aq(eh.value)or""]=],
		},
		{
			[=[if eh and eh.value and not eh.listening and not e1(dU)then]=],
			[=[if eh and eh.value and not eh.statusOnly and not eh.listening and not e1(dU)then]=],
		},
		{
			[=[bs(bh,bi,bj,bk,as,12,8,av.hairline*g)if ld then]=],
			[=[bs(bh,bi,bj,bk,as,12,8,av.hairline*g)bg(bh+1,bi+1,bj-2,3,y(0,0,0),89,0,g)cb(bh+1,bi+1,(bj-2)/3,2,y(72,149,184),y(151,95,172),90,g)cb(bh+1+(bj-2)/3,bi+1,(bj-2)/3,2,y(151,95,172),y(202,86,94),90,g)cb(bh+1+2*(bj-2)/3,bi+1,(bj-2)/3,2,y(202,86,94),y(156,192,73),90,g)if ld then]=],
		},
	}

	for PatchIndex, Patch in Patches do
		local Applied
		Source, Applied = ReplacePlainOnce(Source, Patch[1], Patch[2])
		if not Applied then
			return OriginalSource, false
		end
	end

	return Source, true
end

local function LoadUiLibrary()
	local Success, Result = pcall(function()
		local Source = game:HttpGet("https://raw.githubusercontent.com/neaxusxgod-png/INS-ui/main/uilib.min.lua")
		assert(type(Source) == "string" and #Source > 0, "empty UI library response")

		Source, UiStatusEntriesSupported = AddUiStatusEntrySupport(Source)
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

AimbotSection:Label("profile: Global Anarchy | 132640332499066")
AimbotSection:Label(function()
	return "resolver: " .. Runtime.AimStatus
end)

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
end):Tooltip("Uses Roblox teams when Global Anarchy exposes them.")

AimbotSection:Toggle("sticky aim", true, function(Value)
	Flags.StickyAim = Value
	ClearLock()
end):Tooltip("Keeps the current target after it leaves the FOV. Releasing the aim key still clears it.")

local DrawFovToggle = AimbotSection:Toggle("draw fov", Flags.DrawFov, function(Value)
	Flags.DrawFov = Value
end):Tooltip("Show or hide the FOV circle without changing target selection.")

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
):Tooltip("Maximum target acquisition distance in Roblox studs.")

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
):Tooltip("0% snaps instantly; higher values follow the target more gradually.")

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
):Tooltip("Enable several hitboxes; the closest enabled point is selected each frame.")

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
):Tooltip("Select one preset, switch directly to another, or click the active preset again to clear it.")

local AutoPredictionToggle = PredictionSection:Toggle("auto prediction", true, function(Value)
	Flags.AutoPrediction = Value
end)

if UiStatusEntriesSupported then
	AutoPredictionToggle:AddKeybind("on", "Always")
	AutoPredictionToggle.item.keybind.statusOnly = true
end

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
GravitySlider:Tooltip("Vertical compensation in studs per second squared.")

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
):Tooltip("Uses half of measured round-trip ping; lower this if the aim leads too far.")

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
):Tooltip("Baseline presets; tune them for each Global Anarchy weapon.")

local SilentAimToggle = SilentSection:Toggle("silent aim", false, function(Value)
	Flags.SilentAim = Value
	if not Value then
		SilentAimStatus.Text = "inactive"
	end
end):Tooltip("Exports SilentAim(origin); the new game's shot function must call it.")

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
end):Tooltip("Maximum cursor distance from the selected hitbox.")

SilentSection:Slider("max range", Flags.SilentMaxDistance, 25, 100, 5000, "u", function(Value)
	Flags.SilentMaxDistance = Value
end):Tooltip("Maximum world distance for Silent Aim target selection.")

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
	EspStatus.Text = Value and "starting..." or "stopping..."
end)

EspPlayerSection:Toggle("Roblox team check", false, function(Value)
	Flags.EspTeamCheck = Value
end):Tooltip("Uses Roblox teams when Global Anarchy exposes them.")

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

ChamsToggle:Tooltip("Through-wall translucent body fill using Matcha's external Drawing renderer.")

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
end):Tooltip("Player ESP range in Roblox studs.")

EspRangeSection:Label(function()
	return "status: " .. EspStatus.Text
end)

local SettingsTab = Win:AddSettingsTab("cog")
local ScriptSettingsSection = SettingsTab:Section("script", "Right")
ScriptSettingsSection:Button("unload script", function()
	Runtime.Unload()
end):Tooltip("Disconnect every loop, remove every drawing, and close this menu.")

pcall(function()
	local Sections = SettingsTab._tab.sections
	local ScriptSection = ScriptSettingsSection._section
	local ConfigIndex
	local ScriptIndex

	for Index, Section in Sections do
		if Section.name == "Configs" then
			ConfigIndex = Index
		elseif Section == ScriptSection then
			ScriptIndex = Index
		end
	end

	if ConfigIndex and ScriptIndex then
		table.remove(Sections, ScriptIndex)
		if ScriptIndex < ConfigIndex then
			ConfigIndex = ConfigIndex - 1
		end
		table.insert(Sections, ConfigIndex + 1, ScriptSection)
	end
end)

local EspBundles = {}
local EspTargetCache = {}
local EspWeaponCache = {}
local EspErrorReported = false
local EspRendererFailed = false
local EspSkippedProperties = {}

local function GetInstanceIdentity(Instance)
	local Address
	pcall(function()
		Address = Instance and Instance.Address
	end)
	if type(Address) == "number" and Address > 0 then
		return tostring(Address)
	end

	local FullName
	pcall(function()
		FullName = Instance and Instance:GetFullName()
	end)
	if FullName and FullName ~= "" then
		return FullName
	end
	return tostring(Instance)
end

local function GetPlayerIdentity(Player)
	local PlayerName
	pcall(function()
		PlayerName = Player and Player.Name
	end)
	if PlayerName and PlayerName ~= "" then
		return PlayerName
	end
	return GetInstanceIdentity(Player)
end

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
	if not Success then
		EspSkippedProperties[Property] = true
	end
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

	Bundle.HealthBackground = CreateDrawingObject("Square")
	Bundle.HealthBar = CreateDrawingObject("Square")
	SetDrawingProperty(Bundle.HealthBackground, "Filled", true)
	SetDrawingProperty(Bundle.HealthBackground, "Color", Color3.fromRGB(0, 0, 0))
	SetDrawingProperty(Bundle.HealthBackground, "Visible", false)
	SetDrawingProperty(Bundle.HealthBackground, "ZIndex", 10)

	SetDrawingProperty(Bundle.HealthBar, "Filled", true)
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

	return Bundle
end

local function HideEspBundle(Bundle)
	if not Bundle then
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
end

local function HideAllEspBundles()
	for _, Bundle in EspBundles do
		HideEspBundle(Bundle)
	end
end

local function SetEspBoxLines(Lines, X, Y, Width, Height, Color, Alpha)
	if not Lines or #Lines < 4 then
		return false
	end

	local TopLeft = Vector2.new(X, Y)
	local TopRight = Vector2.new(X + Width, Y)
	local BottomRight = Vector2.new(X + Width, Y + Height)
	local BottomLeft = Vector2.new(X, Y + Height)

	Lines[1].From = TopLeft
	Lines[1].To = TopRight
	Lines[2].From = TopRight
	Lines[2].To = BottomRight
	Lines[3].From = BottomRight
	Lines[3].To = BottomLeft
	Lines[4].From = BottomLeft
	Lines[4].To = TopLeft

	for _, Line in Lines do
		Line.Color = Color
		Line.Transparency = Alpha
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

local function GetHeldWeaponName(Character)
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
	return nil
end

local function GetCachedWeaponName(Character)
	local Now = tick()
	local CharacterIdentity = GetInstanceIdentity(Character)
	local Cached = EspWeaponCache[CharacterIdentity]
	if Cached and Now < Cached.ExpiresAt then
		return Cached.Name
	end

	local WeaponName = GetHeldWeaponName(Character)
	EspWeaponCache[CharacterIdentity] = {
		Name = WeaponName,
		ExpiresAt = Now + 0.25,
	}
	return WeaponName
end

local function GetEspTarget(Player)
	if not Player then
		return nil
	end

	local PlayerIdentity = GetPlayerIdentity(Player)
	if PlayerIdentity == GetPlayerIdentity(LocalPlayer) or IsEspTeammate(Player) then
		return nil
	end

	local Character = GetPlayerCharacter(Player)
	if not Character then
		EspTargetCache[PlayerIdentity] = nil
		return nil
	end

	local Now = tick()
	local CharacterIdentity = GetInstanceIdentity(Character)
	local Cached = EspTargetCache[PlayerIdentity]
	local Humanoid
	local Head
	local RootPart

	if Cached and Cached.CharacterIdentity == CharacterIdentity and Now < Cached.ExpiresAt then
		Humanoid = Cached.Humanoid
		Head = Cached.Head
		RootPart = Cached.RootPart
	else
		Humanoid, Head, RootPart = ResolveEspCharacter(Character)
		local DisplayName = Player.Name
		pcall(function()
			if Player.DisplayName and Player.DisplayName ~= "" then
				DisplayName = Player.DisplayName
			end
		end)
		Cached = {
			Character = Character,
			CharacterIdentity = CharacterIdentity,
			Humanoid = Humanoid,
			Head = Head,
			RootPart = RootPart,
			DisplayName = DisplayName,
			ExpiresAt = Now + 0.75,
		}
		EspTargetCache[PlayerIdentity] = Cached
	end

	if not RootPart or not Head then
		return nil
	end
	if not GetPartPosition(Head) or not GetPartPosition(RootPart) then
		EspTargetCache[PlayerIdentity] = nil
		return nil
	end

	local Health = 100
	local MaxHealth = 100
	if Humanoid then
		local HealthSuccess = pcall(function()
			Health = Humanoid.Health
			MaxHealth = Humanoid.MaxHealth or MaxHealth
		end)
		if HealthSuccess and Health <= 0 then
			return nil
		end
	else
		pcall(function()
			Health = Character:GetAttribute("Health") or Health
			MaxHealth = Character:GetAttribute("MaxHealth") or math.max(Health, MaxHealth)
		end)
		Health = tonumber(Health) or 100
		MaxHealth = tonumber(MaxHealth) or math.max(Health, 100)
		if Health <= 0 then
			return nil
		end
	end

	Cached.Player = Player
	Cached.Character = Character
	Cached.Head = Head
	Cached.RootPart = RootPart
	Cached.Health = Health
	Cached.MaxHealth = math.max(MaxHealth or 100, 1)
	Cached.WeaponName = Flags.EspWeapon and GetCachedWeaponName(Character) or nil
	return Cached
end

local function GetEspBox(Target)
	local HeadPosition = GetPartPosition(Target.Head)
	local RootPosition = GetPartPosition(Target.RootPart)
	if not HeadPosition or not RootPosition then
		return nil
	end
	if Target.Head == Target.RootPart or math.abs(HeadPosition.Y - RootPosition.Y) < 0.15 then
		local HeightOffset = 2.75
		pcall(function()
			HeightOffset = math.max(Target.RootPart.Size.Y * 0.5, HeightOffset)
		end)
		HeadPosition = RootPosition + Vector3.new(0, HeightOffset, 0)
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

local function UpdateEspBundle(Bundle, Target, Camera, Origin)
	local TargetPosition = GetPartPosition(Target.RootPart)
	if not TargetPosition then
		return false
	end

	if not Origin then
		return false
	end

	local Distance = (Origin - TargetPosition).Magnitude
	if Distance > Flags.EspMaxDistance then
		return false
	end

	local X, Y, Width, Height = GetEspBox(Target)
	if not X then
		return false
	end

	if Flags.EspChams and Bundle.Chams then
		Bundle.Chams.Position = Vector2.new(X + 2, Y + 2)
		Bundle.Chams.Size = Vector2.new(math.max(Width - 4, 1), math.max(Height - 4, 1))
		Bundle.Chams.Color = Flags.EspChamsColor
		Bundle.Chams.Transparency = Flags.EspChamsAlpha
		Bundle.Chams.Visible = true
	elseif Bundle.Chams then
		Bundle.Chams.Visible = false
	end

	if Flags.EspBox then
		SetEspBoxLines(
			Bundle.BoxOutline,
			X,
			Y,
			Width,
			Height,
			Color3.fromRGB(0, 0, 0),
			Flags.EspBoxAlpha
		)
		SetEspBoxLines(Bundle.Box, X, Y, Width, Height, Flags.EspBoxColor, Flags.EspBoxAlpha)
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
		Bundle.HealthBackground.Transparency = 0.9
		Bundle.HealthBackground.Visible = true

		Bundle.HealthBar.Position = Vector2.new(X - 5, Y + Height - 1 - BarHeight)
		Bundle.HealthBar.Size = Vector2.new(2, BarHeight)
		Bundle.HealthBar.Color = Color3.new(1 - HealthRatio, HealthRatio, 0)
		Bundle.HealthBar.Transparency = 1
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
		Bundle.Name.Text = Target.DisplayName
		Bundle.Name.Position = Vector2.new(X + Width * 0.5, Y - 15)
		Bundle.Name.Color = Flags.EspTextColor
		Bundle.Name.Transparency = Flags.EspTextAlpha
		Bundle.Name.Visible = true
	elseif Bundle.Name then
		Bundle.Name.Visible = false
	end

	local InfoParts = {}
	if Flags.EspDistance then
		InfoParts[#InfoParts + 1] = "[" .. tostring(math.floor(Distance + 0.5)) .. "u]"
	end
	if Flags.EspWeapon then
		local WeaponName = Target.WeaponName
		if WeaponName then
			InfoParts[#InfoParts + 1] = WeaponName
		end
	end
	if #InfoParts > 0 and Bundle.Info then
		Bundle.Info.Text = table.concat(InfoParts, "  ")
		Bundle.Info.Position = Vector2.new(X + Width * 0.5, Y + Height + 2)
		Bundle.Info.Color = Flags.EspTextColor
		Bundle.Info.Transparency = Flags.EspTextAlpha
		Bundle.Info.Visible = true
	elseif Bundle.Info then
		Bundle.Info.Visible = false
	end

	if Bundle.Flag and Flags.LockedPlayerName == Target.Player.Name then
		Bundle.Flag.Text = "TARGET"
		Bundle.Flag.Position = Vector2.new(X + Width + 4, Y)
		Bundle.Flag.Color = Color3.fromRGB(149, 192, 33)
		Bundle.Flag.Transparency = 1
		Bundle.Flag.Visible = true
	elseif Bundle.Flag then
		Bundle.Flag.Visible = false
	end

	if Flags.EspSnapline and Bundle.SnaplineOutline and Bundle.Snapline then
		local ViewportSize
		pcall(function()
			ViewportSize = Camera.ViewportSize
		end)
		if ViewportSize then
			local From = Vector2.new(ViewportSize.X * 0.5, ViewportSize.Y)
			local To = Vector2.new(X + Width * 0.5, Y + Height)
			Bundle.SnaplineOutline.From = From
			Bundle.SnaplineOutline.To = To
			Bundle.SnaplineOutline.Transparency = Flags.EspSnaplineAlpha
			Bundle.SnaplineOutline.Visible = true

			Bundle.Snapline.From = From
			Bundle.Snapline.To = To
			Bundle.Snapline.Color = Flags.EspSnaplineColor
			Bundle.Snapline.Transparency = Flags.EspSnaplineAlpha
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

	Bundle.LastDrawnAt = tick()
	return true
end

local function UpdateEspFrame()
	if not Flags.Running or not Flags.EspEnabled then
		HideAllEspBundles()
		EspStatus.Text = "off"
		return
	end
	if EspRendererFailed then
		HideAllEspBundles()
		if not EspStatus.LastError then
			EspStatus.Text = "renderer unavailable"
		end
		return
	end

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

	local PlayerCount = 0
	local ValidCount = 0
	local DrawnCount = 0
	local ActiveBundles = {}
	local LocalPlayerIdentity = GetPlayerIdentity(LocalPlayer)
	for _, Player in Players:GetPlayers() do
		if GetPlayerIdentity(Player) ~= LocalPlayerIdentity then
			PlayerCount = PlayerCount + 1
		end

		local Bundle
		local Success, WasDrawn = pcall(function()
			local Target = GetEspTarget(Player)
			if Target then
				ValidCount = ValidCount + 1
				Bundle = GetEspBundle(Player)
				if Bundle then
					return UpdateEspBundle(Bundle, Target, Camera, Origin)
				end
			end
			return false
		end)
		if not Success and not EspErrorReported then
			ReportEspError("player update failed", WasDrawn)
		elseif Success and WasDrawn then
			DrawnCount = DrawnCount + 1
			ActiveBundles[Bundle] = true
		end
	end

	local Now = tick()
	for _, Bundle in EspBundles do
		if
			not ActiveBundles[Bundle]
			and (not Bundle.LastDrawnAt or Now - Bundle.LastDrawnAt > 0.08)
		then
			HideEspBundle(Bundle)
		end
	end

	if not EspStatus.LastError then
		if Runtime.ModelScanActive and ValidCount == 0 then
			EspStatus.Text = "scanning models..."
		else
			EspStatus.Text = tostring(DrawnCount)
				.. "/"
				.. tostring(ValidCount)
				.. " drawn | "
				.. tostring(PlayerCount)
				.. " players"
		end
		if Runtime.ControllerResolverSeen then
			EspStatus.Text = EspStatus.Text .. " | controller"
		elseif Runtime.ControllerRigCount then
			EspStatus.Text = EspStatus.Text .. " | " .. tostring(Runtime.ControllerRigCount) .. " rigs"
		end
		if next(EspSkippedProperties) then
			EspStatus.Text = EspStatus.Text .. " | compat"
		end
	end
end

TrackConnection(RunService.RenderStepped:Connect(function()
	if not Flags.Running then
		return
	end

	local Now = tick()
	if Flags.EspEnabled then
		if Now - (EspStatus.LastUpdate or 0) < 1 / 60 then
			return
		end
	elseif EspStatus.Text == "off" then
		return
	end
	EspStatus.LastUpdate = Now

	local Success, ErrorMessage = pcall(UpdateEspFrame)
	if not Success then
		ReportEspError("ESP frame failed", ErrorMessage)
	end
end))

local FovCircleOutline = TrackDrawing(Drawing.new("Circle"))
FovCircleOutline.Thickness = 3
FovCircleOutline.NumSides = 64
FovCircleOutline.Color = Color3.fromRGB(0, 0, 0)
FovCircleOutline.Visible = false

local FovCircle = TrackDrawing(Drawing.new("Circle"))
FovCircle.Thickness = 1
FovCircle.NumSides = 64
FovCircle.Visible = false
FovCircle.ZIndex = 5

local SilentStatusUpdatedAt = -math.huge

TrackConnection(RunService.RenderStepped:Connect(function()
	if not Flags.Running then
		return
	end

	local Mouse = LocalPlayer:GetMouse()
	local MousePosition = Vector2.new(Mouse.X, Mouse.Y)
	local ShowAimFov = Flags.DrawFov
	local ShowSilentFov = Flags.DrawFov and Flags.SilentAim and Flags.SilentFovCheck
	local ShowFov = ShowAimFov or ShowSilentFov
	local DisplayFovRadius = 0
	if ShowAimFov then
		DisplayFovRadius = math.max(DisplayFovRadius, Flags.FovRadius)
	end
	if ShowSilentFov then
		DisplayFovRadius = math.max(DisplayFovRadius, Flags.SilentFovRadius)
	end

	FovCircleOutline.Position = MousePosition
	FovCircleOutline.Radius = DisplayFovRadius + 1
	FovCircleOutline.Transparency = Flags.FovAlpha
	FovCircleOutline.Visible = ShowFov

	FovCircle.Position = MousePosition
	FovCircle.Radius = DisplayFovRadius
	FovCircle.Color = Flags.FovColor
	FovCircle.Transparency = Flags.FovAlpha
	FovCircle.Visible = ShowFov

	local Now = tick()
	if Flags.SilentAim and Now - SilentStatusUpdatedAt >= 0.1 then
		SilentStatusUpdatedAt = Now
		local Target, ScreenDistance, WorldDistance = FindClosestTarget({
			FovCheck = Flags.SilentFovCheck,
			FovRadius = Flags.SilentFovRadius,
			MaxDistance = Flags.SilentMaxDistance,
		}, MousePosition)
		UpdateSilentTargetStatus(Target, ScreenDistance, WorldDistance)
	elseif not Flags.SilentAim then
		SilentAimStatus.Text = "inactive"
	end
end))

TrackConnection(RunService.Heartbeat:Connect(function(DeltaTime)
	if not Flags.Running then
		return
	end

	if not Flags.Aimbot or not Flags.AimbotActive then
		if LockedPlayer or Flags.LockedPlayerName or SmoothedAimPosition then
			ClearLock()
		end
		Runtime.AimStatus = "hold MouseButton2"
		return
	end

	local Camera = Workspace.CurrentCamera
	if not Camera then
		Runtime.AimStatus = "waiting for camera"
		return
	end

	local Mouse = LocalPlayer:GetMouse()
	local MousePosition = Vector2.new(Mouse.X, Mouse.Y)
	local Target
	local HasStickyLock = Flags.StickyAim and (LockedPlayer ~= nil or Flags.LockedPlayerName ~= nil)
	if HasStickyLock then
		Target = GetLockedTarget(MousePosition)
		if not Target then
			ClearLock()
			Runtime.AimStatus = "lost target"
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
		if Runtime.ModelScanActive then
			Runtime.AimStatus = "scanning models..."
		else
			Runtime.AimStatus = "no target"
		end
		if Runtime.ControllerRigCount and not Runtime.ModelScanActive then
			Runtime.AimStatus = Runtime.AimStatus .. " | " .. tostring(Runtime.ControllerRigCount) .. " rigs"
		end
		return
	end

	local CameraPosition = Camera.Position
	local AimPosition = PredictTargetPosition(Target, CameraPosition)
	if not AimPosition then
		ClearAimSmoothing()
		Runtime.AimStatus = "target has no position"
		return
	end

	local TargetName = Target.Player.Name
	Runtime.AimStatus = "tracking " .. TargetName
	if Runtime.ControllerResolverSeen then
		Runtime.AimStatus = Runtime.AimStatus .. " | controller"
	end
	local Smoothness = math.clamp(Flags.AimSmoothness or 0, 0, 100)
	local LookPosition = AimPosition
	if Smoothness > 0 then
		if SmoothedAimPosition and SmoothedAimTargetName == TargetName then
			local ResponseSpeed = 28 - ((Smoothness / 100) * 26)
			local FrameTime = Clamp(DeltaTime or (1 / 60), 0, 1 / 15)
			local Alpha = math.clamp(1 - math.exp(-ResponseSpeed * FrameTime), 0.01, 1)
			SmoothedAimPosition = SmoothedAimPosition:Lerp(AimPosition, Alpha)
		else
			local CurrentLookPosition
			pcall(function()
				local AimDistance = math.max((AimPosition - CameraPosition).Magnitude, 1)
				CurrentLookPosition = CameraPosition + (Camera.CFrame.LookVector * AimDistance)
			end)
			SmoothedAimPosition = CurrentLookPosition or AimPosition
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
		Runtime.AimStatus = "camera update failed"
	end
end))

Environment.SilentAim = SilentAim
Environment.UnloadDesertStormAim = Runtime.Unload
Environment.__MatchaAimRuntime = Runtime
InitializationComplete = true
