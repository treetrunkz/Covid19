﻿IMPORT $.Types2 AS Types;
IMPORT $.Configuration AS Config;
IMPORT Python3 AS Python;
metric_t := Types.metric_t;
count_t := Types.count_t;
inputRec := Types.InputRec;
statsRec := Types.statsRec;

EXPORT CalcStats := MODULE
  SHARED InfectionPeriod := Config.InfectionPeriod;
  SHARED PeriodDays := Config.PeriodDays;
  SHARED ScaleFactor := Config.ScaleFactor;  // Lower will give more hot spots.
  SHARED MinActDefault := Config.MinActDefault; // Minimum cases to be considered emerging, by default.
  SHARED MinActPer100k := Config.MinActPer100k; // Minimum active per 100K population to be considered emerging.
  SHARED infectedConfirmedRatio := Config.InfectedConfirmedRatio; // Calibrated by early antibody testing (rough estimate),
                                                                  // and ILI Surge statistics.
  SHARED locDelim := Config.LocDelim; // Delimiter between location terms.

  SHARED DATASET(statsRec) smoothData(DATASET(statsRec) recs) := FUNCTION
    // Filter out any daily increases that imply an R > 10.
    // This is to deal with situations where a locality changes their reporting policy and dumps a large batch
    // of cases or deaths into a single day.
    // We do this by computing a 7-day moving average and setting new cases or deaths to the 7-day average if
    // the implied growth would be greater than R=10.
    // In the process, we add the 7-day MAs, as well as adjusted cumulative counts.  All growth stats are then based
    // on the adjusted counts.
    statsRecE := RECORD(statsRec)
      SET OF count_t casesHistory := [];
      SET OF count_t deathsHistory := [];
    END;
    // Calculate the 7-day MA
    recs1 := DISTRIBUTE(recs, HASH32(location));
    // Sort by location and ascending date
    recs2 := SORT(recs1, location, date, LOCAL);
    // Convert to extended record
    recs3 := PROJECT(recs2, TRANSFORM(statsRecE, SELF := LEFT));
    // Smooth data and calculate basic inter-period stats while we're at it.
    statsRecE calc7dma(statsRecE le, statsRecE ri) := TRANSFORM
      newCases := IF(le.location = ri.location, ri.cumCases - le.cumCases, ri.cumCases);
      //newCases := IF(le.location = ri.location AND ri.cumCases > le.cumCases, ri.cumCases - le.cumCases, 0);
      REAL cases7dma := IF(le.location != ri.location OR COUNT(le.casesHistory) = 0, 0, AVE(le.casesHistory));
      // Calculate adjusted cases and deaths tp remove large dumps of cases or deaths as follows:
      // - If the new value is > 2.24 * 7 day moving average (implying R > 10)
      //    limit new cases / deaths it to 2.24 * 7 day average
      // - Calculate new cumulative values by adding up adjusted new values.
      REAL adjNewCases := IF(cases7dma > 10 AND newCases > 2.24 * cases7dma, cases7dma * 2.24, MAX(newCases, 0));
      casesHist := IF(le.location != ri.location, ri.casesHistory, [adjNewCases] + le.casesHistory)[..7];
      SELF.casesHistory := casesHist;
      SELF.cases7dma := ROUND(cases7dma);
      SELF.newCases := ROUND(adjNewCases);
      SELF.prevCases := IF(le.location = ri.location, le.cumCases, 0);
      SELF.adjPrevCases := IF(le.location = ri.location, le.adjCumCases, 0);
      SELF.adjCumCases := SELF.adjPrevCases + ROUND(adjNewCases);
      SELF.caseAdjustment := ROUND(adjNewCases - newCases);
      newDeaths := IF(le.location = ri.location, ri.cumDeaths - le.cumDeaths, ri.cumDeaths);
      //newDeaths := IF(le.location = ri.location AND ri.cumDeaths > le.cumDeaths, ri.cumDeaths - le.cumDeaths, 0);
      REAL deaths7dma := IF(le.location != ri.location OR COUNT(le.deathsHistory) = 0, 0, AVE(le.deathsHistory));
      REAL adjNewDeaths := IF(deaths7dma > 10 AND newDeaths > 2.25 * deaths7dma, deaths7dma * 2.25, MAX(newDeaths, 0));
      deathsHist := IF(le.location != ri.location, ri.deathsHistory, [adjNewDeaths] + le.deathsHistory)[..7];
      SELF.deathsHistory := deathsHist;
      SELF.deaths7dma := ROUND(deaths7dma);
      SELF.newDeaths := ROUND(adjNewDeaths);
      SELF.prevDeaths := IF(le.location = ri.location, le.cumDeaths, 0);
      SELF.adjPrevDeaths := IF(le.location = ri.location, le.adjCumDeaths, 0);
      SELF.adjCumDeaths := SELF.adjPrevDeaths + ROUND(adjNewDeaths);
      SELF.deathsAdjustment := ROUND(adjNewDeaths - newDeaths);
      SELF.population := ri.population;
      SELF := ri;
    END;
    recs4 := ITERATE(recs3, calc7dma(LEFT, RIGHT), LOCAL);
    recs5 := SORT(recs4, location, -date);
    recs6 := PROJECT(recs5, statsRec);
    return recs6;
  END;
  EXPORT DATASET(statsRec) DailyStats(DATASET(inputRec) stats, UNSIGNED level, UNSIGNED asOfDate = 0) := FUNCTION
    // Fiter stats to start at asOfDate
    stats0 := IF(asOfDate = 0, stats, stats(date < asOfDate));
    // Add composite location information
    statsRec addLocation(inputRec inp, UNSIGNED lev) := TRANSFORM
      L0Loc := 'The World';
      L1Loc := inp.Country;
      L2Loc := inp.Country + locDelim + inp.Level2;
      L3Loc := inp.Country + locDelim + inp.Level2 + locDelim + inp.Level3;
      SELF.Location := IF(lev = 3, L3Loc, IF(lev = 2, L2Loc, IF(lev=1, L1Loc, L0Loc)));
      SELF := inp;
    END;
    stats1 := PROJECT(stats0, addLocation(LEFT, level));
    // Add record id
    stats2 := SORT(stats1, location, -date);
    stats3 := PROJECT(stats2, TRANSFORM(RECORDOF(LEFT), SELF.id := COUNTER, SELF := LEFT));
    // Get rid of any obsolete locations (i.e. locations that don't have data for the latest date)
    latestDate := MAX(stats3, date);
    obsoleteLocations := DEDUP(stats3, location)(date < latestDate);
    stats4 := JOIN(stats3, obsoleteLocations, LEFT.location = RIGHT.location, LEFT ONLY);
    // Remove spurious data dumps by smoothing and 
    // compute basic delta stats between latest period and previous period
    stats5 := smoothData(stats4);
    // Go infectionPeriod days back to see how many have recovered and how many are still active per SIR model
    statsRec calcSIR(statsRec curr, statsRec prev) := TRANSFORM
      // Use adjusted case and death counts to calculate SIR attributes.  Spurious dumps are not time synchronized,
      // so should not be considered for SIR calculations, which are time dependent      INTEGER case_adjustment := curr.adjCumCases - curr.cumCases;
      INTEGER death_adjustment := curr.adjCumDeaths - curr.cumDeaths;
      // Total deaths and cases should reflect actual reported totals, and we must maintain the equality:
      // cumCases = Active + Recovered + cumDeaths.  Active must filter out untimely reporting.  Untimely cases
      // are allocated to Recovered.  Untimely deaths are ignored for the purpose of these calculations.
      INTEGER newDeaths := curr.adjCumDeaths - prev.adjCumDeaths;
      INTEGER active := curr.adjCumCases - prev.adjCumCases;
      INTEGER prevActive := curr.adjCumCases - prev.adjCumCases;
      INTEGER recovered := curr.cumCases - active - curr.cumDeaths;
      SELF.recovered := IF(recovered > 0, recovered, 0);
      SELF.active := IF(active > 0, active, 0);
      SELF.prevActive := IF(prevActive > 0, prevActive, 0);
      SELF.cfr := curr.adjCumDeaths / prev.adjCumCases;
      SELF := curr;
    END;
    stats6 := JOIN(stats5, stats5, LEFT.location = RIGHT.location AND LEFT.id = RIGHT.id - InfectionPeriod,
                        calcSIR(LEFT, RIGHT));
    RETURN stats6;
  END;  // Daily Stats
  EXPORT statsRec RollupStats(DATASET(statsRec) stats, UNSIGNED rollupLevel) := FUNCTION
    // Valid rollup levels are 1 or 2.  Since 3 is the lowest level
    statsG0 := GROUP(SORT(stats, date), date);
    statsG1 := GROUP(SORT(stats, Country, date), Country, date);
    statsG2 := GROUP(SORT(stats, Country, Level2, date), Country, Level2, date);
    statsG := IF(rollupLevel = 0, statsG0, IF(rollupLevel = 1, statsG1, statsG2));
    statsRec doRollup(statsRec rec, DATASET(statsRec) children) := TRANSFORM
      locName := IF(rollupLevel = 0, 'The World', IF(rollupLevel = 1, rec.Country, rec.Country + locDelim + rec.Level2));
      SELF.location := locName;
      SELF.Country := IF(rollupLevel = 0, '', rec.Country);
      SELF.Level2 := IF(rollupLevel <= 1, '', rec.Level2);
      SELF.Level3 := '';
      SELF.date := rec.date;
      // Counts can be simply summed to get the rollup value
      SELF.cumCases := SUM(children, cumCases);
      SELF.cumDeaths := SUM(children, cumDeaths);
      SELF.cumHosp := SUM(children, cumHosp);
      SELF.tested := SUM(children, tested);
      SELF.negative := SUM(children, negative);
      SELF.positive := SUM(children, positive);
      SELF.population := SUM(children, population);
      SELF.prevCases := SUM(children, prevCases);
      SELF.newCases := SUM(children, newCases);
      SELF.prevDeaths := SUM(children, prevDeaths);
      SELF.newDeaths := SUM(children, newDeaths);
      SELF.active := SUM(children, active);
      SELF.prevActive := SUM(children, prevActive);
      SELF.recovered := SUM(children, recovered);
      SELF.cases7dma := SUM(children, cases7dma);
      SELF.deaths7dma := SUM(children, deaths7dma);
      SELF.adjCumCases := SUM(children, adjCumCases);
      SELF.adjCumDeaths := SUM(children, adjCumDeaths);
      SELF.adjPrevCases := SUM(children, adjPrevCases);
      SELF.adjPrevDeaths := SUM(children, adjPrevDeaths);
      SELF.caseAdjustment := SUM(children, caseAdjustment);
      SELF.deathsAdjustment := SUM(children, deathsAdjustment);
      // CFR will be calculated later.
      SELF.cfr := 0;
    END;
    statsRolled := ROLLUP(statsG, GROUP, doRollup(LEFT, ROWS(LEFT)));
    RETURN SORT(statsRolled, location, -date);
  END; // RollupStats
  EXPORT DATASET(StatsRec) MergeStats(DATASET(StatsRec) rollupRecs, DATASET(StatsRec) sourceRecs, UNSIGNED level) := FUNCTION
    // Favor the rolled up record if it exists, otherwise take the source record
    // But if the source record exist, take fips, lat and long from the source, since the rollup
    // can't determine those.
    merged0 := JOIN(rollupRecs, sourceRecs, LEFT.location = RIGHT.location AND LEFT.date = RIGHT.date,
                    TRANSFORM(RECORDOF(LEFT),
                              SELF.fips := RIGHT.fips,
                              SELF.latitude := RIGHT.latitude,
                              SELF.longitude := RIGHT.longitude,
                              SELF.population := IF(LEFT.population > 1, LEFT.population, RIGHT.population),
                              SELF := IF(LEFT.location != '', LEFT, RIGHT)), FULL OUTER);
    merged1 := SORT(merged0, location, -date);
    // Recalculate CFR in case some of the lower level locations don't have population data.
    // Add record id
    merged2 := PROJECT(merged1, TRANSFORM(RECORDOF(LEFT), SELF.id := COUNTER, SELF := LEFT));
    merged := JOIN(merged2, merged2, LEFT.location = RIGHT.location AND LEFT.id = RIGHT.id - InfectionPeriod, TRANSFORM(RECORDOF(LEFT),
                        SELF.cfr := LEFT.adjCumDeaths / RIGHT.adjCumCases,
                        SELF := LEFT), LEFT OUTER);
    RETURN merged;

  END;
END; // CalcStats