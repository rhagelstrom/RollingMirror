local superOnAttack = {};
local nextFreeId = 0;
local originalRolls = {};

function onInit()
	superOnAttack = ActionAttack.onAttack; -- Stash original away
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

	-- Find the original attack roll. Shity FG code doesnt allow for passing arguments to handlers
	local originalRoll = originalRolls[rRoll.originalRollId];
	Debug.console(originalRolls);
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

-- Based on ActionManager.getDefenseValue
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
	
	-- Results
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
	if  numMirrorImages > 0 then
		local originalRoll = { rSource = rSource, rRoll = rRoll };
		rollMirrorImageCheck(rTarget, originalRoll, numMirrorImages);
	else 
		superOnAttack(rSource, rTarget, rRoll);
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
	local rRoll = { sType = "mirrorImage", sDesc = "[MIRROR CHECK]", aDice = { "d20" }, nMod = 0 };
	rRoll.numMirrorImages = numImages;
	
	-- Hacky way of passing the roll info to the mirrorImage handler
	rRoll.originalRollId = nextFreeId;
	originalRolls[tostring(nextFreeId)] = originalRoll;
	nextFreeId = nextFreeId + 1;
	
	ActionsManager.performAction(nil, actor, rRoll);
end