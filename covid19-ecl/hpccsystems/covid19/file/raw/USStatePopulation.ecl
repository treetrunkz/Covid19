EXPORT USStatePopulation := MODULE

  EXPORT filePath := '~hpccsystems::covid19::file::raw::usstatepopulation::v1::sc-est2018-agesex-civ.csv';  
                       

  EXPORT layout := RECORD
    STRING SUMLEV;
    STRING REGION;
    STRING DIVISION;
    STRING STATE;
    STRING NAME;
    STRING SEX;
    STRING AGE;
    STRING ESTBASE2010_CIV;
    STRING POPEST2010_CIV;
    STRING POPEST2011_CIV;
    STRING POPEST2012_CIV;
    STRING POPEST2013_CIV;
    STRING POPEST2014_CIV;
    STRING POPEST2015_CIV;
    STRING POPEST2016_CIV;
    STRING POPEST2017_CIV;
    STRING POPEST2018_CIV;
  END;


  EXPORT ds := DATASET(filePath, layout, CSV(HEADING(1)));  


END;