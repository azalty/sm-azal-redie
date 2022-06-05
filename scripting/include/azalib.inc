/** Double-include prevention */
#if defined _AzaLib_included_
  #endinput
#endif
#define _AzaLib_included_

// AzaLib version: 1.0.1

/**
 * Rounds a floating point number using the "Round to nearest, ties away from zero" rounding rule.
 * This rule is the default one you learn in maths.
 * Rounds to the nearest value; if the number falls midway,
 * it is rounded to the nearest value above (for positive numbers) or below (for negative numbers)
 *
 * @param value			Floating point value to round.
 * @return				The value rounded to the nearest integer.
 */
stock int AzaLib_RoundHalfAwayZero(float value)
{
	if (value % 1 == 0.5)
	{
		if (value > 0)
			return RoundToFloor(value) + 1;
		else
			return RoundToFloor(value);
	}
	return RoundToNearest(value);
}

/**
 * Converts a STEAM_0 to STEAM_1 (just changes the number)
 * Doesn't do anything if already STEAM_1
 * This is meant to allow STEAM_0 as user inputs in a plugin
 *
 * @param steamid		The STEAM_0 or STEAM_1 steamid.
 * @param maxlength		Maximum length of your steamid string.
 * @param reverse		If true, converts STEAM_1 to STEAM_0 instead.
 */
stock void AzaLib_FixSteamID(char[] steamid, int maxlength, bool reverse=false)
{
	if (!reverse)
		ReplaceString(steamid, maxlength, "STEAM_0", "STEAM_1");
	else
		ReplaceString(steamid, maxlength, "STEAM_1", "STEAM_0");
}

/**
 * Returns a random integer between two bounds.
 * More accurate than GetRandomInt() 
 *
 * @param min			Minimum random bound.
 * @param max			Maximum random bound.
 * @return 				A random number between (inclusive) min and max.
 */
stock int AzaLib_RandomInt(int min, int max)
{
	return RoundToZero(GetURandomFloat() * (max-min+1) + min);
}