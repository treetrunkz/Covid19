IMPORT hpccsystems.covid19.file.public.JohnHopkins as JH;
IMPORT hpccsystems.covid19.file.public.DailyMetrics as DM;
IMPORT hpccsystems.covid19.metrics.Types as types;
IMPORT STD;



EXPORT Files := MODULE
  SHARED today := STD.date.TODAY();
  SHARED yesterday := today - 1;

  EXPORT dailyGlobal := DATASET('~hpccsystems::covid19::file::public::metrics::daily_global.flat', Types.statsExtRec, FLAT);
  EXPORT dailyCountries := DM.countries;
  EXPORT dailyCounties := DM.counties;
  EXPORT dailyStates := DM.states;

  EXPORT dailyCountries_confirmed := GROUP(dailyCountries, location)(date = today - 1) ;
  EXPORT dailyStates_confirmed := GROUP(dailyStates, location)(date = today - 1) ;
  EXPORT dailyCounties_confirmed := GROUP(dailyCounties, location)(date = today - 1) ;


  EXPORT prefix := '~hpccsystems::covid19::file::raw::johnhopkins::scraped::';
  EXPORT world_cumconfirmed      := prefix + 'world_cumulative_confirmed.csv';
  EXPORT world_newCases          := prefix + 'world_newCases.csv';
  EXPORT country_cumdeaths       := prefix + 'country_cumulative_deaths.csv';
  EXPORT country_cumconfirmed    := prefix + 'country_cumulative_confirmed.csv';
  EXPORT state_cumdeaths         := prefix + 'states_cumulative_deaths.csv';
  EXPORT us_cumDeaths            := prefix + 'us_cumulative_deaths.csv';
  EXPORT us_cumConfirmed         := prefix + 'us_cumulative_confirmed.csv';
  EXPORT county_cumDeaths        := prefix + 'county_cumulative_deaths.csv';
  EXPORT county_cumConfirmed     := prefix + 'county_cumulative_confirmed.csv';
  EXPORT global_update           := prefix + 'global_' + (STRING) today + '.csv';

  EXPORT rglobal := RECORD
    UNSIGNED Date;
    UNSIGNED Total_Cases;
    UNSIGNED Total_Deaths;
    UNSIGNED Total_Recovered;
    UNSIGNED Active_Cases;
    UNSIGNED Closed_Cases;
END;
  EXPORT global_update_ds := DATASET(global_update, RGLOBAL, CSV(HEADING(1)));
  EXPORT world_cumconfirmed_ds := DATASET(world_cumconfirmed, {UNSIGNED4 date, UNSIGNED confirmed}, CSV(HEADING(1)));
  EXPORT world_newCases_ds := DATASET(world_newCases, {UNSIGNED4 date, UNSIGNED newCases}, CSV(HEADING(1)));

  EXPORT country_cumdeaths_ds := DATASET(country_cumdeaths, {STRING country, UNSIGNED deaths}, CSV(HEADING(1)));
  EXPORT country_cumconfirmed_ds := DATASET(country_cumconfirmed, {UNSIGNED confirmed, STRING country}, CSV(HEADING(1)));

  EXPORT state_cumdeaths_ds := DATASET(state_cumdeaths, {STRING state, UNSIGNED deaths}, CSV(HEADING(1)));

  EXPORT us_cumdeaths_ds := DATASET(us_cumdeaths, {UNSIGNED4 date, UNSIGNED deaths}, CSV(HEADING(1)));
  EXPORT us_cumconfirmed_ds := DATASET(us_cumconfirmed, {UNSIGNED4 date, UNSIGNED confirmed}, CSV(HEADING(1)));

  EXPORT county_cumdeaths_ds := DATASET(county_cumdeaths, {STRING county, UNSIGNED deaths}, CSV(HEADING(1)));
  EXPORT county_cumconfirmed_ds := DATASET(county_cumconfirmed, {STRING county, UNSIGNED confirmed}, CSV(HEADING(1)));

END;