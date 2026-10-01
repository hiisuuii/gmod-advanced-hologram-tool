-- AdvHologram.Set(ent, enabled) is server-side only. It networks to
-- all clients, including late joins. AdvHologram.IsHologram(ent) works on
-- either side. A hologram's move children are drawn with it automatically,
-- which covers a player's active weapon and anything bonemerged on. For
-- entities that belong to a hologram without being parented to it, return a
-- table of them from the clientside hook GM:AdvHologramGatherChildren(ent).

if SERVER then AddCSLuaFile() end

AdvHologram = AdvHologram or {}
AdvHologram.Active = AdvHologram.Active or {}

function AdvHologram.IsHologram(ent)
	return IsValid(ent) and AdvHologram.Active[ent:EntIndex()] == true
end

if SERVER then
	util.AddNetworkString("AdvHologram.Set")
	util.AddNetworkString("AdvHologram.Sync")
	util.AddNetworkString("AdvHologram.RequestSync")

	function AdvHologram.Set(ent, enabled)
		if not IsValid(ent) or ent:IsWorld() then return end

		local index = ent:EntIndex()
		AdvHologram.Active[index] = enabled or nil
		ent:SetNWBool("AdvHologramEnabled", enabled)

		net.Start("AdvHologram.Set")
			net.WriteUInt(index, 16)
			net.WriteBool(enabled)
		net.Broadcast()
	end

	net.Receive("AdvHologram.RequestSync", function(_, ply)
		if ply.AdvHologramSynced then return end
		ply.AdvHologramSynced = true

		local indices = {}
		for index in pairs(AdvHologram.Active) do
			indices[#indices + 1] = index
		end

		net.Start("AdvHologram.Sync")
			net.WriteUInt(#indices, 16)
			for _, index in ipairs(indices) do
				net.WriteUInt(index, 16)
			end
		net.Send(ply)
	end)

	-- Entity indices get recycled, so a stale entry would turn an unrelated
	-- entity into a hologram later. Clients cannot do this themselves: their
	-- EntityRemoved also fires when an entity merely leaves the PVS.
	hook.Add("EntityRemoved", "AdvHologram.Forget", function(ent)
		local index = ent:EntIndex()
		if not AdvHologram.Active[index] then return end

		AdvHologram.Active[index] = nil

		net.Start("AdvHologram.Set")
			net.WriteUInt(index, 16)
			net.WriteBool(false)
		net.Broadcast()
	end)
end

if not CLIENT then return end

AdvHologram.Style = {
	-- Distances are world units, scroll rates units/second with negative going
	-- up. tintGain wants to be well above 1: the reference drives blue to 3.0
	-- so lit areas clip to white instead of reading as flat blue paint.
	color = Color(102, 159, 255),
	tintGain = 3,
	tintAmount = 0.6,

	-- The thin scanline color is baked into holo_lines.vtf, not adjustable here.
	lineSpacing = 2.5,
	bandTile = 400,
	bandStrength = 0.5,
	bandScroll = -50,

	rimStrength = 1.5,
	opacity = 0.5,

	glitchStrength = 1,
	glitchPeriod = 3,
	glitchLength = 0.25,
	noiseTile = 200,
	noiseScroll = -25,
}

local LINES_PER_TILE = 32

local BASE_PARAMS = {
	["$pixshader"] = "hisuiholo_ps20b",
	["$vertexshader"] = "hisuiholo_vs20",

	["$basetexture"] = "hisui/sw/holo_lines",
	["$texture1"] = "hisui/sw/holo_lines",
	["$texture2"] = "hisui/sw/holo_distort",
	["$texture3"] = "_rt_FullFrameFB",

	["$linearwrite"] = 1,
	["$linearread_basetexture"] = 1,
	["$linearread_texture1"] = 1,
	["$linearread_texture2"] = 1,
	["$linearread_texture3"] = 1,

	["$model"] = 1,
	["$softwareskin"] = 1,
	["$vertexnormal"] = 1,
	["$cull"] = 1,
	["$depthtest"] = 1,
}

local materials = {}
local materialCount = 0

-- 31 rather than 32 so full white lands on exactly 1.0 and stays untinted
local COLOR_STEPS = 31
local MAX_MATERIALS = 256
local warnedMaterialCap = false
local warnedFrameSize = false

local function quantize(channel)
	return math.Round(channel / 255 * COLOR_STEPS)
end

local function holoMaterial(name, r, g, b)
	local key = name .. "|" .. r .. "," .. g .. "," .. b
	local cached = materials[key]
	if cached then return cached end

	if materialCount >= MAX_MATERIALS
		and not (r == COLOR_STEPS and g == COLOR_STEPS and b == COLOR_STEPS)
	then
		if not warnedMaterialCap then
			warnedMaterialCap = true
			ErrorNoHalt("[AdvHologram] material cache hit " .. MAX_MATERIALS ..
				" entries; further entity colors will render untinted.\n")
		end
		return holoMaterial(name, COLOR_STEPS, COLOR_STEPS, COLOR_STEPS)
	end

	local source = Material(name)
	local mat = CreateMaterial("hisui_holo_" .. string.gsub(key, "[^%w]", "_"), "screenspace_general", BASE_PARAMS)

	local diffuse = source and not source:IsError() and source:GetTexture("$basetexture")
	if diffuse then
		mat:SetTexture("$basetexture", diffuse)
	end
	mat:SetTexture("$texture3", render.GetScreenEffectTexture())

	mat:SetFloat("$c2_x", r / COLOR_STEPS)
	mat:SetFloat("$c2_y", g / COLOR_STEPS)
	mat:SetFloat("$c2_z", b / COLOR_STEPS)

	materials[key] = mat
	materialCount = materialCount + 1
	return mat
end

local function pushConstants()
	local s = AdvHologram.Style
	local c = s.color
	local t = CurTime()
	local gain = s.tintGain / 255

	local lineScale = 1 / (s.lineSpacing * LINES_PER_TILE)
	local bandScale = 1 / s.bandTile
	local noiseScale = 1 / s.noiseTile

	local bandScroll = (t * s.bandScroll * bandScale) % 1
	local noiseScroll = (t * s.noiseScroll * noiseScale) % 1

	local glitch = s.glitchStrength * (1 - math.min(1, (t % s.glitchPeriod) / s.glitchLength))

	-- The shader samples the framebuffer copy at the raw screen UV, which
	-- assumes _rt_FullFrameFB is viewport-sized. It always is in practice.
	local frame = render.GetScreenEffectTexture()
	if not warnedFrameSize and (frame:Width() ~= ScrW() or frame:Height() ~= ScrH()) then
		warnedFrameSize = true
		ErrorNoHalt("[AdvHologram] _rt_FullFrameFB is " .. frame:Width() .. "x" .. frame:Height() ..
			" but the viewport is " .. ScrW() .. "x" .. ScrH() ..
			"; what shows through holograms will be offset.\n")
	end

	for _, mat in pairs(materials) do
		mat:SetFloat("$c0_x", c.r * gain)
		mat:SetFloat("$c0_y", c.g * gain)
		mat:SetFloat("$c0_z", c.b * gain)
		mat:SetFloat("$c0_w", s.tintAmount)

		mat:SetFloat("$c1_x", lineScale)
		mat:SetFloat("$c1_y", bandScale)
		mat:SetFloat("$c1_z", s.bandStrength)
		mat:SetFloat("$c1_w", bandScroll)

		-- c2.xyz is the entity color, fixed when the material is created
		mat:SetFloat("$c2_w", glitch)

		mat:SetFloat("$c3_x", s.rimStrength)
		mat:SetFloat("$c3_y", s.opacity)
		mat:SetFloat("$c3_z", noiseScale)
		mat:SetFloat("$c3_w", noiseScroll)
	end
end

local drawingHolograms = false

local function renderHologram(ent, flags)
	if not drawingHolograms then
		if halo.RenderedEntity() == ent then
			ent:DrawModel(flags)
		end
		return
	end

	local model = ent:GetModel()
	local names = ent.AdvHologramMaterials
	if not names or ent.AdvHologramModel ~= model then
		names = ent:GetMaterials() or {}
		ent.AdvHologramMaterials = names
		ent.AdvHologramModel = model
	end

	local color = ent:GetColor()
	local r, g, b = quantize(color.r), quantize(color.g), quantize(color.b)

	for i = 1, math.min(#names, 32) do
		render.MaterialOverrideByIndex(i - 1, holoMaterial(names[i], r, g, b))
	end

	ent:DrawModel(flags)

	render.MaterialOverrideByIndex()
end

local overridden = {}
local targets = {}
local inTargets = {}

-- Only here so a parenting cycle cant hang the frame
local MAX_DEPTH = 8

local function apply(ent)
	ent.RenderOverride = renderHologram
	ent.AdvHologramOverridden = true
	ent.AdvHologramMaterials = nil
	ent.AdvHologramModel = nil
	ent:DrawShadow(false)
end

local function clear(ent)
	if not IsValid(ent) then return end

	ent.RenderOverride = nil
	ent.AdvHologramOverridden = nil
	ent.AdvHologramMaterials = nil
	ent.AdvHologramModel = nil
	ent:DrawShadow(true)
end

local function drawable(ent, localPlayer, drawLocal)
	return IsValid(ent)
		and not ent:IsWorld()
		and not ent:IsDormant()
		and not ent:IsEffectActive(EF_NODRAW)
		and (ent ~= localPlayer or drawLocal)
end

local function gather(ent, depth, localPlayer, drawLocal)
	if depth > MAX_DEPTH or inTargets[ent] then return end
	if not drawable(ent, localPlayer, drawLocal) then return end

	inTargets[ent] = true
	targets[#targets + 1] = ent

	for _, child in ipairs(ent:GetChildren()) do
		gather(child, depth + 1, localPlayer, drawLocal)
	end

	local extra = hook.Run("AdvHologramGatherChildren", ent)
	if istable(extra) then
		for _, child in ipairs(extra) do
			gather(child, depth + 1, localPlayer, drawLocal)
		end
	end
end

local function refreshTargets(localPlayer, drawLocal)
	for i = #targets, 1, -1 do
		targets[i] = nil
	end
	for ent in pairs(inTargets) do
		inTargets[ent] = nil
	end

	for index in pairs(AdvHologram.Active) do
		gather(Entity(index), 0, localPlayer, drawLocal)
	end

	for ent in pairs(overridden) do
		if not inTargets[ent] then
			clear(ent)
			overridden[ent] = nil
		end
	end

	for i = 1, #targets do
		local ent = targets[i]
		if not overridden[ent] then
			apply(ent)
			overridden[ent] = true
		end
	end
end


hook.Add("PostDrawOpaqueRenderables", "AdvHologram.Draw", function(isDrawingDepth, isDrawingSkybox, isDraw3DSkybox)
	if isDrawingDepth or isDrawingSkybox or isDraw3DSkybox then return end
	if not next(AdvHologram.Active) and not next(overridden) then return end

	local localPlayer = LocalPlayer()
	local drawLocal = IsValid(localPlayer) and localPlayer:ShouldDrawLocalPlayer()

	refreshTargets(localPlayer, drawLocal)
	if #targets == 0 then return end

	pushConstants()
	render.UpdateScreenEffectTexture()

	render.OverrideDepthEnable(true, true)
	drawingHolograms = true

	for i = 1, #targets do
		local ent = targets[i]
		ent:SetupBones()
		ent:DrawModel()
	end

	drawingHolograms = false
	render.OverrideDepthEnable(false, false)
end)

local function setClient(index, enabled)
	AdvHologram.Active[index] = enabled or nil
end

net.Receive("AdvHologram.Set", function()
	setClient(net.ReadUInt(16), net.ReadBool())
end)

net.Receive("AdvHologram.Sync", function()
	for _ = 1, net.ReadUInt(16) do
		setClient(net.ReadUInt(16), true)
	end
end)

hook.Add("InitPostEntity", "AdvHologram.RequestSync", function()
	net.Start("AdvHologram.RequestSync")
	net.SendToServer()
end)

for _, ent in ipairs(ents.GetAll()) do
	if ent.AdvHologramOverridden then
		clear(ent)
	end
end

local function describeOverride(ent)
	local fn = ent.RenderOverride
	if not fn then return "none" end
	if fn == renderHologram then return "ours" end

	-- source, not short_src: the latter caps at 60 characters and truncates the
	-- front, which is where the addon folder name is.
	local info = debug.getinfo(fn, "S")
	if not info then return "TAKEN by unknown" end

	return "TAKEN by " .. string.gsub(info.source, "^@", "") .. ":" .. info.linedefined
end

concommand.Add("advhologram_debug", function()
	local count = 0
	for _ in pairs(AdvHologram.Active) do count = count + 1 end

	MsgN("--- AdvHologram ---")
	MsgN("dxlevel: ", render.GetDXLevel(), render.GetDXLevel() < 90 and "  TOO LOW, custom pixel shaders need 90+" or "")
	MsgN("pixel shader file: ", file.Exists("shaders/fxc/hisuiholo_ps20b.vcs", "GAME") and "found" or "MISSING")
	MsgN("vertex shader file: ", file.Exists("shaders/fxc/hisuiholo_vs20.vcs", "GAME") and "found" or "MISSING")
	MsgN("lines texture: ", file.Exists("materials/hisui/sw/holo_lines.vtf", "GAME") and "found" or "MISSING")
	MsgN("noise texture: ", file.Exists("materials/hisui/sw/holo_distort.vtf", "GAME") and "found" or "MISSING")
	MsgN("holograms active: ", count, ", drawn last frame: ", #targets, ", materials cached: ", materialCount)

	local trace = LocalPlayer():GetEyeTrace().Entity
	if IsValid(trace) then
		MsgN("traced ", tostring(trace), ": hologram=", tostring(AdvHologram.IsHologram(trace)),
			" RenderOverride=", describeOverride(trace))
	end

	for _, ent in ipairs(ents.GetAll()) do
		if AdvHologram.IsHologram(ent) and ent.RenderOverride ~= renderHologram then
			MsgN("CONFLICT on ", tostring(ent), ": RenderOverride ", describeOverride(ent))
		end
	end
end)
