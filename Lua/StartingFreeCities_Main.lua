print("*Loaded HV Starting Free Cities script*");

-- ----------------------------------
-- Variables
-- ----------------------------------

-- get options from advanced setup screen.
local iDesiredFreeCities = GameConfiguration.GetValue("HV_FreeCityCount") or 9;
print("Target number of Free Cities from setup screen: " .. iDesiredFreeCities)

local bRenameForProximity = GameConfiguration.GetValue("HV_RenameFreeCityForProximity");
if bRenameForProximity == true then
	print("bRenameForProximity is true");
else
	print("bRenameForProximity is false");
end

-- get width and height of map
local iMapW, iMapH = Map.GetGridSize();

-- empty table to store city locations in
local aCityPlots = {};
local aMajorStartPlots = {};

-- min distance between free cities should be the same as min distance between city states
local iMinDistance = GlobalParameters.START_DISTANCE_MINOR_CIVILIZATION_START or 5;

-- --------------------------------
-- Functions
-- --------------------------------

-- spawns units from BonusMinorStartingUnits table around this plot.
function SpawnFreeCityUnits (iPlotX, iPlotY)
	local iPlayerID = 62; -- TO DO: should probably look this up instead of assuming FreeCities is always player 62
	local pPlayer = Players[iPlayerID]; 
		
	-- get current era
	local iEraID = pPlayer:GetEra();
	--local sCurrentEra = "ERA_MEDIEVAL";
	local sEraType = GameInfo.Eras[iEraID].EraType;
	print("Era is " .. sEraType);
	
	-- get list of units to place in this era.
	local aUnitList = {};

	for Row in GameInfo.BonusMinorStartingUnits() do
		-- ignore units for different eras, or that require a district.
		-- also ignore builders, because the AI for Free Cities won't use them
		if Row.Era == sEraType and Row.OnDistrictCreated == false and Row.Unit ~= "UNIT_BUILDER" then
			-- add the quantity specified for to the list
			for i = 1, Row.Quantity do
				table.insert(aUnitList, Row.Unit);
			end
		end
	end
	
	-- loop through each unit in the placement list.
	local iDirection = 0;
	for i, sUnitType in ipairs(aUnitList) do
			
		-- get plot adjacent to the city.
		print("checking adjacent plot direction " .. iDirection);
		local pPlot = Map.GetAdjacentPlot(iPlotX, iPlotY, iDirection);
		if pPlot == nil then 
			print("invalid plot. skipping this unit.")
		else
			
			local iX = pPlot:GetX();
			local iY = pPlot:GetY();
			
			-- create a unit here.
			local iUnitTypeID = GameInfo.Units[sUnitType].Index;
			
			local pPlayerUnits = pPlayer:GetUnits();
			
			local pNewUnit = pPlayerUnits:Create( iUnitTypeID, iX, iY );
			
			if pNewUnit == nil then 
				print( "failed to spawn a " .. sUnitType .. " on plot (" .. iX .. "," .. iY .. "). putting it on a valid nearby plot instead." );
				UnitManager.InitUnitValidAdjacentHex(iPlayerID, sUnitType, iX, iY, 1);
			else
				print( "spawned a " .. sUnitType .. " on plot (" .. iX .. "," .. iY .. ")" );
			end;
			
			-- iterate direction fat end of loop, so units end up in a circle around city.
			iDirection = iDirection + 1;
			if iDirection > 5 then iDirection = 0 end;
		end
	end
end


-- spawns a free city at a random point on the map, making sure it's far enough away from existing cities & settlers
function SpawnFreeCity ()
	--print("assembling list of valid land plots")
	local aLandPlots = {};
	
	-- loop through each plot on the map to build a list of possible locations
	for iX = 0, iMapW do
		for iY = 0, iMapH do
			local pPlot = Map.GetPlot(iX, iY);
			
			-- exclude plots that are water or impassible to units (e.g. mountains)
			if (pPlot ~= nil and pPlot:IsWater() == false and pPlot:IsImpassable() == false) then
				
				-- exclude plots that are too close to an existing city
				if HV_TooCloseToAnyPlot(pPlot, aCityPlots, iMinDistance) == false then
					table.insert(aLandPlots, pPlot);
				end
			end
		end
	end

	print("found " .. #aLandPlots .. " valid land plots");

	if #aLandPlots <= 0 then
		print("ran out of valid locations to spawn free cities")
		return false;
	end
	
	-- pick one of those plots at random
	local iRoll =  math.random(#aLandPlots);
	local pPlot = aLandPlots[iRoll];
	if pPlot == nil then 
		print("plot " .. pPlot:GetX() .. "," .. pPlot:GetY() .. " does not exist");
		return false;
	end
	
	-- put a city there, belonging to Free Cities, who are always player number 62
	local pPlayer = Players[62];
	if pPlayer == nil then
		print("could not find player number 62: Free Cities")
		return false;
	end
	local pPlayerCities = pPlayer:GetCities();
	local pCity = pPlayerCities:Create( pPlot:GetX(), pPlot:GetY() );
	if pCity == nil then 
		print("failed to spawn city on plot " .. pPlot:GetX() .. "," .. pPlot:GetY() .. " for unknown reason");
		return false;
	end
	print("spawned free city of " .. Locale.Lookup( pCity:GetName() ) .. " on plot " .. pPlot:GetX() .. "," .. pPlot:GetY())

	-- spawn starting units around the city
	print("placing starting units around plot " .. pPlot:GetX() .. "," .. pPlot:GetY() );
	SpawnFreeCityUnits( pPlot:GetX(), pPlot:GetY() );
	
	-- rename city based on closes major civ, if that option was chosen in advanced setup
	if bRenameForProximity == true then
		-- get nearest strt positions
		local pNearestStartPosition = HV_NearestPlotInList (pPlot, aMajorStartPlots);
		--print("the nearest major civ start location is at plot " .. pNearestStartPosition:GetX() .. "," .. pNearestStartPosition:GetY() );
		-- get the civ who owns the settler in that start position
		local sPlayerType = "NONE";
		local aUnitsInPlot = Units.GetUnitsInPlot(pNearestStartPosition);
		for i, pUnit in ipairs(aUnitsInPlot) do
			if GameInfo.Units[pUnit:GetType()].FoundCity == true then 
				local iOwnerID = pUnit:GetOwner();
				local pPlayerConfig = PlayerConfigurations[iOwnerID];
				sPlayerType = pPlayerConfig:GetCivilizationTypeName();
			end
		end
		print("the nearest major civ is " .. sPlayerType);
		
		-- get a list of city names for this civ
		local aNameList = {}
		for Row in GameInfo.CityNames() do
			if Row.CivilizationType == sPlayerType then
				table.insert(aNameList, 1, Row.CityName); -- insert each name at pos 1, so table ends up in reverse order
			end
		end
		
		-- pick first name from the list that hasn't already been used
		for i = 1, #aNameList do
			local sNewName = aNameList[i];
			if HV_NameAlreadyTaken(sNewName) == false then
				-- rename the city
				pCity:SetName(sNewName);
				print("naming it " .. sNewName);
				break;
			end
		end

	end
	
	-- add this city to the list so we can't spawn another city too close to it.
	table.insert(aCityPlots, pPlot);
	return true;
end


-- accepts a plot, list of plots, and a distance. Returns true if tested plot is within that distance of any of the listed plots.
function HV_TooCloseToAnyPlot (pTestPlot, plotList, iMinDistance)
	
	if pTestPlot == nil then print("pTestPlot is nil!") end;
	if plotList == nil then print("plotList is nil!") end;
	if iMinDistance == nil then print("iMinDistance is nil!") end;
	
	-- loop through all plots in the list
	for index, pPlot in ipairs(plotList) do
		-- check distance from this plot to test plot.
		if pPlot == nil then print("pPlot is nil!") end
		--print("pPlot value is: " .. pPlot:GetX() .. "," .. pPlot:GetY() );
		--print("pTestPlot value is: " .. pTestPlot:GetX() .. "," .. pTestPlot:GetY() );
		local iDistanceFromTestPlot = Map.GetPlotDistance( pPlot:GetX(), pPlot:GetY(), pTestPlot:GetX(), pTestPlot:GetY() );
		
		-- if it's too close, return true
		if iDistanceFromTestPlot < iMinDistance then
			return true;
		end
	end 
	-- if none of the plots were too close, return false.
	return false;
end

-- accepts a plot and list of plots. Returns plot from the list that's nearest on map to input plot.
function HV_NearestPlotInList (pTestPlot, aPlotList)

	if pTestPlot == nil then print("pTestPlot is nil!") end;
	if aPlotList == nil then print("aPlotList is nil!") end;
	
	local pResultPlot = nil;
	local iResultDistance = nil;
	
	-- loop through all plots in the list
	for index, pPlot in ipairs(aPlotList) do
	
		if pPlot == nil then print("pPlot is nil!") end
		-- check distance from this plot to test plot.
		local iTestDistance = Map.GetPlotDistance( pPlot:GetX(), pPlot:GetY(), pTestPlot:GetX(), pTestPlot:GetY() );
		
		-- is it closer than our best result so far?
		if iResultDistance == nil or iTestDistance < iResultDistance then
			pResultPlot = pPlot;
			iResultDistance = iTestDistance;
		end
	end
	
	-- after we've checked all plots, return the closest one.
	return pResultPlot;
end

-- checks all cities currently on the map, returns true if any of their names matches the input string.
function HV_NameAlreadyTaken (sDesiredName)
	local sDesiredName = Locale.Lookup( sDesiredName );
	
	-- loop through all players
	local aPlayers = PlayerManager.GetAlive();
	for _, pPlayer in ipairs(aPlayers) do
		local pPlayerConfig = PlayerConfigurations[pPlayer:GetID()];
		local sPlayerType = pPlayerConfig:GetCivilizationTypeName();
		local pCities = pPlayer:GetCities();
		
		-- loop through all cities this player owns
		for index, pCity in pCities:Members() do	
			local sCityName = Locale.Lookup( pCity:GetName() );
			
			-- return true if this city name matches input.
			if  sCityName == sDesiredName then
				return true;
			end
		end	
	end

	-- if we didn't find a match, return false.
	return false;
end

-- ------------------------------
-- Main
-- ------------------------------

-- check whether this is a newly created game or a savegame that's been loaded
local iGameStartTurn = GameConfiguration.GetStartTurn();
local iTurnNum = Game.GetCurrentGameTurn();
print("Start turn is " .. iGameStartTurn .. " Current turn is  " .. iTurnNum );

if iTurnNum ~= iGameStartTurn then
	print("this is a savegame, not a newly created game. Doing nothing.");
else
	print("this is a newly created game.");
	print("recording positions of starting settlers");
	-- loop through all players
	local aPlayers = PlayerManager.GetAlive();
	for _, pPlayer in ipairs(aPlayers) do
		local pPlayerConfig = PlayerConfigurations[pPlayer:GetID()];
		local sPlayerType = pPlayerConfig:GetCivilizationTypeName();
		local pPlayerUnits = pPlayer:GetUnits();
		--print("Player " .. sPlayerType .. " is in the game ")
		
		-- loop through all units this player owns
		for _, pUnit in pPlayerUnits:Members() do

			-- look for units with the FoundCity flag rather than for UNIT_SETTLER, in case any mods add a unique settler unit
			if GameInfo.Units[pUnit:GetType()].FoundCity == true then 
				
				-- get the plot the unit is on
				local pPlot = Map.GetPlot( pUnit:GetX(), pUnit:GetY() );
				
				if pPlot then -- With the free city states mod, this can be Null
					-- add plot to the table of city plots, so free cities won't spawn too close to it.
					print(sPlayerType .. " has a settler on plot " .. pPlot:GetX() .. "," .. pPlot:GetY() );
					table.insert(aCityPlots, pPlot );
				
					if pPlayer:IsMajor() then
						table.insert(aMajorStartPlots, pPlot );
					end
				end
			end

		end
	end
	print("beginning placement of free cities");
	-- keep calling the city spawning function until desired number is reached, or it returns false.
	if iDesiredFreeCities > 0 then -- 0 shouldn't run
		for i = 1, iDesiredFreeCities do -- Match number
			if SpawnFreeCity() == false then
				print("could not place all free cities. Placed " .. i .. " out of " .. iDesiredFreeCities .. " requested")
				break;
			end
			if i == iDesiredFreeCities then
				print("placed all free cities successfully");
			end
		end
	end
end