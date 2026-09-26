-- Exemplo Pasta Framework v2 — recria a UI antiga (nursultan.lua) via API nova
-- Como carregar:
--   local Pasta = loadstring(game:HttpGet("https://raw.githubusercontent.com/SEU_REPO/main/PastaLib.lua"))()
-- Para teste local (loadfile no executor):
--   local Pasta = loadstring(readfile("PastaLib.lua"))()

local Pasta = loadstring(readfile("PastaLib.lua"))() -- dev local
-- publicado: loadstring(game:HttpGet("https://raw.githubusercontent.com/SEU_REPO/main/PastaLib.lua"))()

local Window = Pasta:CreateWindow({
	Name = "pasta",
	Logo = "rbxassetid://139568612294283",
	Footer = "pasta pastaland pashyu nurik kak ded",
	ToggleKey = Enum.KeyCode.RightShift,
	ShowHUD = true,
})

-- Tabs (categoria agrupa com header na sidebar, igual ao antigo Features/Manager)
local Combat = Window:AddTab({ Name = "Combat", Icon = "Combat", Category = "Features" })
local Movement = Window:AddTab({ Name = "Movement", Icon = "Movement", Category = "Features" })
local Visuals = Window:AddTab({ Name = "Visuals", Icon = "Visuals", Category = "Features" })
local Player = Window:AddTab({ Name = "Player", Icon = "Player", Category = "Features" })
local Misc = Window:AddTab({ Name = "Misc", Icon = "Misc", Category = "Features" })
local Presets = Window:AddTab({ Name = "Presets", Icon = "Presets", Category = "Manager" })
local AutoBuy = Window:AddTab({ Name = "Auto Buy", Icon = "AutoBuy", Category = "Manager" })
local Accounts = Window:AddTab({ Name = "Accounts", Icon = "Accounts", Category = "Manager" })

-- Conteudo antigo: Fighting / Base na coluna 1, Tools / Other na coluna 2
local cardFighting = Combat:AddCard({ Title = "Fighting", Column = 1 })
cardFighting:AddToggle({ Name = "Attack Aura", Flag = "fighting_attack_aura" })
cardFighting:AddToggle({ Name = "No Velocity", Flag = "fighting_no_velocity" })
cardFighting:AddToggle({ Name = "Trigger Bot", Flag = "fighting_trigger_bot" })
cardFighting:AddToggle({ Name = "Aim Assist", Keybind = "F1", Flag = "fighting_aim_assist" })
cardFighting:AddToggle({ Name = "Auto Explosion", Flag = "fighting_auto_explosion" })

local cardBase = Combat:AddCard({ Title = "Base", Column = 1 })
cardBase:AddToggle({ Name = "Auto Swap", Default = true, Flag = "base_auto_swap" })
cardBase:AddToggle({ Name = "Item Release", Flag = "base_item_release" })

local cardTools = Combat:AddCard({ Title = "Tools", Column = 2 })
cardTools:AddToggle({ Name = "Sprint Reset", Flag = "tools_sprint_reset" })
cardTools:AddToggle({ Name = "Tape Mouse", Flag = "tools_tape_mouse" })
cardTools:AddToggle({ Name = "Aim Assist", Description = "Helps to Focus on Entities", Flag = "tools_aim_assist" })
cardTools:AddToggle({ Name = "Web Trap", Flag = "tools_web_trap" })

local cardOther = Combat:AddCard({ Title = "Other", Column = 2 })
cardOther:AddToggle({ Name = "No Slot Change", Flag = "other_no_slot" })
cardOther:AddToggle({ Name = "Anti Bot", Flag = "other_anti_bot" })
cardOther:AddToggle({ Name = "No Friend Damage", Default = true, Flag = "other_no_friend_damage" })

-- Componentes novos que o script antigo nao tinha (mesma cara pasta)
local demo = Misc:AddCard({ Title = "Framework Demo", Column = 1 })
demo:AddSlider({ Name = "Reach", Min = 0, Max = 30, Default = 12, Increment = 1, Suffix = " studs", Flag = "demo_reach" })
demo:AddDropdown({ Name = "Mode", Options = { "Balanced", "Performance", "Quality" }, Default = "Balanced", Flag = "demo_mode" })
demo:AddKeybind({ Name = "Panic key", Default = Enum.KeyCode.X, Flag = "demo_panic" })
demo:AddButton({ Name = "Save config", Callback = function()
	Pasta.Config:Save("default")
	Pasta:Notify({ Title = "pasta", Description = "Config salva." })
end })
demo:AddButton({ Name = "Load config", Callback = function()
	Pasta.Config:Load("default")
	Pasta:Notify({ Title = "pasta", Description = "Config carregada." })
end })

-- Busca, HUD, tema e handles funcionam sem codigo extra:
--   Window:GetTab("Combat"):Select()
--   Window:SetHUDVisible(false)
--   Pasta:SetTheme(Pasta:CreateTheme({ Accent = Color3.fromRGB(0, 220, 255) }))

Pasta:Notify({ Title = "pasta", Description = "Framework v2 carregado.", Duration = 4 })
