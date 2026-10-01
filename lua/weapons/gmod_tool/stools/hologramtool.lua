TOOL.Category = "Hisui's Tools"
TOOL.Name = "Hologram Maker"
TOOL.Command = nil
TOOL.ConfigName = ""

if CLIENT then
	language.Add("tool.hologramtool.name", "Hologram Maker")
	language.Add("tool.hologramtool.desc", "Enable/Disable hologram FX on an entity")
	language.Add("tool.hologramtool.0", "Left click to enable/disable hologram FX for the entity you're looking at. Right click to enable/disable hologram FX for yourself.")

	function TOOL.BuildCPanel(pnl)
		pnl:AddControl("Header", {Text = "Hologram Tool", Description = [[Left-Click to enable/disable hologram FX for the entity you're looking at.
		Right click to enable/disable hologram FX for yourself.
		]]})
	end

	local function notify(ent, name)
		if not IsValid(ent) then return end
		notification.AddLegacy((ent:GetNWBool("AdvHologramEnabled") and "Disabled" or "Enabled") .. " hologram FX for " .. name .. ".", NOTIFY_GENERIC, 5)
		surface.PlaySound("buttons/button14.wav")
	end

	function TOOL:LeftClick(tr)
		if not IsFirstTimePredicted() then return true end
		if not IsValid(tr.Entity) or tr.Entity:IsWorld() then return false end

		notify(tr.Entity, language.GetPhrase("#" .. tr.Entity:GetClass()))
		return true
	end

	function TOOL:RightClick(tr)
		if not IsFirstTimePredicted() then return true end

		local owner = self:GetOwner()
		notify(owner, owner:Nick())
		return true
	end

	return
end

function TOOL:LeftClick(tr)
	local ent = tr.Entity
	if not IsValid(ent) or ent:IsWorld() then return false end

	AdvHologram.Set(ent, not ent:GetNWBool("AdvHologramEnabled"))
	return true
end

function TOOL:RightClick(tr)
	local owner = self:GetOwner()
	AdvHologram.Set(owner, not owner:GetNWBool("AdvHologramEnabled"))
	return true
end
