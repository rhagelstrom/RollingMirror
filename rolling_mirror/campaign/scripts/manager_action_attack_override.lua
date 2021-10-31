local superOnAttack = {};
local nextFreeId = 0;
local originalRolls = {};

function onInit()
	superOnAttack = ActionAttack.onAttack; -- Stash original away
	ActionAttack.onAttack = onAttack;
	ActionsManager.registerResultHandler("attack", onAttack);
	ActionsManager.registerResultHandler("mirrorImage", onMirrorImageHit);

	-- Add the effect to the spell
	DataSpell.parsedata["mirror image"] = { getMirrorImageEffect(3) };
end

function getMirrorImageEffect(numImages)
	local effect = { type = "effect", sTargeting = "self", nDuration = 1, sUnits = "minute" };
	effect.sName = "Mirror Image: " .. numImages .. "; (C)"

	return effect;
end

function onMirrorImageHit(rSource, rTarget, rRoll)
	-- Print the mirror roll in chat
	local rMessage = ActionsManager.createActionMessage(rSource, rRoll);
	Comm.deliverChatMessage(rMessage);

	-- Find the original attack roll. Shitty FG code doesnt allow for passing arguments to handlers
	local originalRoll = originalRolls[rRoll.originalRollId];
	originalRolls[rRoll.originalRollId] = nil;

	local numMirrorImages = math.min(rRoll.numMirrorImages, 20 - 1); -- max checked outside
	if isMirrorImageHit(numMirrorImages, ActionsManager.total(rRoll)) then
		local hit = onAttackMirrorImage(originalRoll.rSource, rSource, originalRoll.rRoll);
		if hit then
			decrementMirrorImages(rSource, numMirrorImages);
		end
	else
		superOnAttack(originalRoll.rSource, rSource, originalRoll.rRoll);
	end
end

function decrementMirrorImages(rActor, currentNumImages)
	local newNumImages = currentNumImages - 1;

	EffectManager.removeEffect(ActorManager.getCTNode(rActor), "% *[Mm]irror% +[Ii]mage% *");
	if newNumImages > 0 then
		EffectManager.addEffect("", "", ActorManager.getCTNode(rActor), getMirrorImageEffect(newNumImages), false);
	end
end

-- Based on ActionManager.getDefenceValue
function getMirrorImageDefenseValue(rAttacker, rMirroredTarget, rRoll)
	-- Base calculations
	local sAttack = rRoll.sDesc;
	
	local sAttackType = string.match(sAttack, "%[ATTACK.*%((%w+)%)%]");
	local bOpportunity = string.match(sAttack, "%[OPPORTUNITY%]");
	local nCover = tonumber(string.match(sAttack, "%[COVER %-(%d)%]")) or 0;

	local nDefense = 10 + ActorManager5E.getAbilityBonus(rMirroredTarget, "dexterity");
	-- Effects
	local nDefenseEffectMod = 0;
	local bADV = false;
	local bDIS = false;
	if ActorManager.hasCT(rMirroredTarget) then
		local nBonusStat = 0;
		local nBonusSituational = 0;
		
		local aAttackFilter = {};
		if sAttackType == "M" then
			table.insert(aAttackFilter, "melee");
		elseif sAttackType == "R" then
			table.insert(aAttackFilter, "ranged");
		end
		if bOpportunity then
			table.insert(aAttackFilter, "opportunity");
		end

		local bProne = false;
		if EffectManager5E.hasEffect(rAttacker, "ADVATK", rMirroredTarget, true) then
			bADV = true;
		end
		if EffectManager5E.hasEffect(rAttacker, "DISATK", rMirroredTarget, true) then
			bDIS = true;
		end
		if EffectManager5E.hasEffect(rAttacker, "Invisible", rMirroredTarget, true) then
			bADV = true;
		end
		if EffectManager5E.hasEffect(rMirroredTarget, "GRANTADVATK", rAtracker) then
			bADV = true;
		end
		if EffectManager5E.hasEffect(rMirroredTarget, "GRANTDISATK", rAtracker) then
			bDIS = true;
		end
		if EffectManager5E.hasEffect(rMirroredTarget, "Invisible", rAttacker) then
			bDIS = true;
		end
		if EffectManager5E.hasEffect(rMirroredTarget, "Paralyzed", rAttacker) then
			bADV = true;
		end
		if EffectManager5E.hasEffect(rMirroredTarget, "Prone", rAttacker) then
			bProne = true;
		end
		if EffectManager5E.hasEffect(rMirroredTarget, "Restrained", rAttacker) then
			bADV = true;
		end
		if EffectManager5E.hasEffect(rMirroredTarget, "Stunned", rAttacker) then
			bADV = true;
		end
		if EffectManager5E.hasEffect(rMirroredTarget, "Unconscious", rAttacker) then
			bADV = true;
			bProne = true;
		end
		
		if bProne then
			if sAttackType == "M" then
				bADV = true;
			elseif sAttackType == "R" then
				bDIS = true;
			end
		end
		
		if nCover < 5 then
			local aCover = EffectManager5E.getEffectsByType(rMirroredTarget, "SCOVER", aAttackFilter, rAttacker);
			if #aCover > 0 or EffectManager5E.hasEffect(rMirroredTarget, "SCOVER", rAttacker) then
				nBonusSituational = nBonusSituational + 5 - nCover;
			elseif nCover < 2 then
				aCover = EffectManager5E.getEffectsByType(rMirroredTarget, "COVER", aAttackFilter, rAttacker);
				if #aCover > 0 or EffectManager5E.hasEffect(rMirroredTarget, "COVER", rAttacker) then
					nBonusSituational = nBonusSituational + 2 - nCover;
				end
			end
		end
		
		nDefenseEffectMod = nBonusSituational;
	end
	
	return nDefense, 0, nDefenseEffectMod, bADV, bDIS;
end

-- Based on ActionManager.onAttack
function onAttackMirrorImage(rSource, rMirroredTarget, rRoll)
	local hit = false;
	ActionsManager2.decodeAdvantage(rRoll);

	local rMessage = ActionsManager.createActionMessage(rSource, rRoll);
	rMessage.text = string.gsub(rMessage.text, " %[MOD:[^]]*%]", "");

	local rAction = {};
	rAction.nTotal = ActionsManager.total(rRoll);
	rAction.aMessages = {};
	
	local nDefenseVal, nAtkEffectsBonus, nDefEffectsBonus = getMirrorImageDefenseValue(rSource, rMirroredTarget, rRoll);
	if nAtkEffectsBonus ~= 0 then
		rAction.nTotal = rAction.nTotal + nAtkEffectsBonus;
		local sFormat = "[" .. Interface.getString("effects_tag") .. " %+d]"
		table.insert(rAction.aMessages, string.format(sFormat, nAtkEffectsBonus));
	end
	if nDefEffectsBonus ~= 0 then
		nDefenseVal = nDefenseVal + nDefEffectsBonus;
		local sFormat = "[" .. Interface.getString("effects_def_tag") .. " %+d]"
		table.insert(rAction.aMessages, string.format(sFormat, nDefEffectsBonus));
	end
	
	local sCritThreshold = string.match(rRoll.sDesc, "%[CRIT (%d+)%]");
	local nCritThreshold = tonumber(sCritThreshold) or 20;
	if nCritThreshold < 2 or nCritThreshold > 20 then
		nCritThreshold = 20;
	end
	
	rAction.nFirstDie = 0;
	if #(rRoll.aDice) > 0 then
		rAction.nFirstDie = rRoll.aDice[1].result or 0;
	end
	if rAction.nFirstDie >= nCritThreshold then
		rAction.bSpecial = true;
		rAction.sResult = "crit";
		hit = true;
		table.insert(rAction.aMessages, "[CRITICAL HIT]");
	elseif rAction.nFirstDie == 1 then
		rAction.sResult = "fumble";
		table.insert(rAction.aMessages, "[AUTOMATIC MISS]");
	elseif nDefenseVal then
		if rAction.nTotal >= nDefenseVal then
			rAction.sResult = "hit";
			hit = true;
			table.insert(rAction.aMessages, "[HIT]");
		else
			rAction.sResult = "miss";
			table.insert(rAction.aMessages, "[MISS]");
		end
	end
	
	Comm.deliverChatMessage(rMessage);
	
	applyAttackAtMirrorImage(rSource, rMirroredTarget, rRoll.bTower, rRoll.sType, rRoll.sDesc, rAction.nTotal, table.concat(rAction.aMessages, " "));
	
	-- REMOVE TARGET ON MISS OPTION
	if (rAction.sResult == "miss" or rAction.sResult == "fumble") then
		if rRoll.bRemoveOnMiss then
			TargetingManager.removeTarget(ActorManager.getCTNodeName(rSource), ActorManager.getCTNodeName(rMirroredTarget));
		end
	end
	
	-- HANDLE FUMBLE/CRIT HOUSE RULES
	local sOptionHRFC = OptionsManager.getOption("HRFC");
	if rAction.sResult == "fumble" and ((sOptionHRFC == "both") or (sOptionHRFC == "fumble")) then
		notifyApplyHRFC("Fumble");
	end
	if rAction.sResult == "crit" and ((sOptionHRFC == "both") or (sOptionHRFC == "criticalhit")) then
		notifyApplyHRFC("Critical Hit");
	end

	return hit;
end

-- Based on ActionManager.applyAttack
function applyAttackAtMirrorImage(rSource, rMirroredTarget, bSecret, sAttackType, sDesc, nTotal, sResults)
	local msgShort = {font = "msgfont"};
	local msgLong = {font = "msgfont"};
	
	msgShort.text = "Attack -> [at Mirror Image]";
	msgLong.text = "Attack [" .. nTotal .. "] -> [at Mirror Image]";
	if sResults ~= "" then
		msgLong.text = msgLong.text .. " " .. sResults;
	end
	
	msgShort.icon = "roll_attack";
	if string.match(sResults, "%[CRITICAL HIT%]") then
		msgLong.icon = "roll_attack_crit";
	elseif string.match(sResults, "HIT%]") then
		msgLong.icon = "roll_attack_hit";
	elseif string.match(sResults, "MISS%]") then
		msgLong.icon = "roll_attack_miss";
	else
		msgLong.icon = "roll_attack";
	end
		
	ActionsManager.messageResult(bSecret, rSource, rMirroredTarget, msgLong, msgShort);
end

function isMirrorImageHit(numMirrorImages, roll)
	local threshold = math.ceil(20 / (numMirrorImages + 1));

	return roll > threshold;
end

function onAttack(rSource, rTarget, rRoll)
	local numMirrorImages = getNumMirrorImages(rTarget);

	local reachDistance = reachDistanceBetween(rSource, rTarget);

	-- TODO: Change forum description that this doesnt work with blindness from light
	-- TODO: Make sure player can see their mirror roll
	if EffectManager5E.hasEffect(rSource, "Blinded", rTarget) then
		sendChatMessage(rSource, rTarget, "Attacker is blinded and cannot see mirror images");
		superOnAttack(rSource, rTarget, rRoll);
	elseif reachDistance ~= -1 and hasAnyVisionWithinRange({ "blindsight", "truesight" }, reachDistance, rSource) then
		sendChatMessage(rSource, rTarget, "Attacker can see through the mirror image illusions");
		superOnAttack(rSource, rTarget, rRoll);
	elseif numMirrorImages > 0 then
		local originalRoll = { rSource = rSource, rRoll = rRoll };
		rollMirrorImageCheck(rTarget, originalRoll, numMirrorImages);
	else 
		superOnAttack(rSource, rTarget, rRoll);
	end
end

function sendChatMessage(rSource, rTarget, text)
	local msg = { font = "msgfont", text = text, icon = "portrait_gm_token" };
	
	ActionsManager.messageResult(false, rSource, rTarget, msg, msg);
end

-- Returns whether this actor has any of the vision types named in aVisionTypes within the specified range
function hasAnyVisionWithinRange(aVisionTypes, nRange, rActor)
	local nodeType, node = ActorManager.getTypeAndNode(rActor);
	if node == nil then
		return false;
	end
	local sSenses = DB.getValue(node, "senses", "");
	local actorVisions = parseVisions(sSenses);

	for _, vision in ipairs(actorVisions) do
		for _, visionType in ipairs(aVisionTypes) do
			if vision.name == visionType and vision.distance >= nRange then
				return true;
			end
		end
	end

	return false;
end

function reachDistanceBetween(rSource, rTarget)
	if rSource == nil or rTarget == nil then
		return -1;
	end
	local srcToken, srcImage = getTokenAndImage(rSource);
    local tgtToken, tgtImage = getTokenAndImage(rTarget);

	if srcToken == nil or tgtToken == nil then
		return -1;
	end

	if srcImage.getDistanceBetween == nil then
		return -1; --This function is only available in FGU.
	end

	return srcImage.getDistanceBetween(srcToken, tgtToken);
end

function getTokenAndImage(rActor)
	if rActor == nil then
		return nil, nil;
	end
	
	local token = CombatManager.getTokenFromCT(rActor.sCTNode);
	local image = ImageManager.getImageControl(token);
	if image == nil or not image.hasGrid() then
		return nil, nil;
	else
		return token, image;
	end
end

-- Based on EffectManager.hasEffect, but that function is trash
function getNumMirrorImages(rActor)
	if not rActor then
		return 0;
	end
	
	-- Iterate through each effect
	local tResults = {};
	for _, v in pairs(ActorManager.getEffects(rActor)) do
		local nActive = DB.getValue(v, "isactive", 0);
		if nActive == 1 then
			local sLabel = DB.getValue(v, "label", "");
			local aEffectComps = EffectManager.parseEffect(sLabel);

			for kEffectComp, sEffectComp in ipairs(aEffectComps) do
				local name, value = string.gmatch(sEffectComp, "(.*)% *:% *([0-9]*)")();
				if name ~= nil and StringManager.trim(name):lower() == "mirror image" and value ~= nil then
					return tonumber(value);
				end
			end
		end
	end

	return 0;
end

function rollMirrorImageCheck(actor, originalRoll, numImages) 
	local rRoll = { sType = "mirrorImage", sDesc = "[MIRROR CHECK]", aDice = { "d20" }, nMod = 0, bTower = false, bSecret = false };
	rRoll.numMirrorImages = numImages;
	
	-- Hacky way of passing the roll info to the mirrorImage handler
	rRoll.originalRollId = nextFreeId;
	originalRolls[tostring(nextFreeId)] = originalRoll;
	nextFreeId = nextFreeId + 1;

	ActionsManager.performAction(nil, actor, rRoll);
end

function parseVisions(sVisions)
	local aVisions = {};
	for s in sVisions:gmatch("([^,]*),?") do
		local sTrim = StringManager.trim(s);
		if sTrim ~= "" then
			local name, value = string.gmatch(sTrim, "(.*)% ([0-9]+).*")();
			if name ~= "" and value ~= "" and name:lower() ~= "passive perception" then
				local vision = { name = name:lower(), distance = tonumber(value) };
				table.insert(aVisions, vision);		
			end
		end
	end
	return aVisions;
end