/*Set up the library where you store the datasets*/
libname sas "yourpath\sample_output";


/***************************************************************************************************/
/*Step 1: Calculating the Propensity Score with imputed data*/
proc import datafile = "yourpath\Data_dictionary_sample.xlsx"
	out = sas.cov dbms = xlsx replace;
	getnames = yes;
	sheet = "DEMO";
run;


proc import datafile = "yourpath\sample_dataset.xlsx"
	out = sas.sample dbms = xlsx replace;
	getnames = yes;
	sheet = "sample";
run;


proc sql noprint; select distinct (variable_name) into :classcov separated by ' ' from sas.cov where Variable_type in ("binary"); quit;
%put &classcov.;


proc sql noprint; select distinct (variable_name) into :categocov separated by ' ' from sas.cov where Variable_type in ("binary") and Variable_name not in ("EXPOSE","MACE_OUTCOME"); quit;
%put &categocov.;


proc sql noprint; select distinct (variable_name) into :continucov separated by ' ' from sas.cov where Variable_type in ("continuous"); quit;
%put &continucov.;



/*Calculate Propensity score using logistic regression*/
proc logistic data=sas.Sample descending;
	class &classcov.;
	model EXPOSE= &categocov. &continucov.;
  output out = sas.Sample_ps (drop = _LEVEL_) p = denom;
run;


/***************************************************************************************************/
/*Step 2: check the distribution of PS before Matching/Weighting*/
data ps_before_weighting; 
	set sas.Sample_ps;
  exp_ps = .;
  non_ps= .;
  if EXPOSE = 1 then exp_ps = denom;
  if EXPOSE = 0 then non_ps = denom;
  keep exp_ps non_ps;
run;


proc sgplot data=ps_before_weighting;
   histogram exp_ps / transparency=0.75 fillattrs=(color="#0096A0") binwidth=0.05 legendlabel='Treatment A';
   density exp_ps / lineattrs=(color="#007B82" thickness=2) legendlabel='Treatment A';

   histogram non_ps / transparency=0.75 fillattrs=(color="#D85F58") binwidth=0.05 legendlabel='Treatment B';
   density non_ps / lineattrs=(color="#B5483D" thickness=2) legendlabel='Treatment B';

   keylegend / location=outside position=bottom;
   xaxis label="Propensity Score Distribution (before applying PS method)" values=(0 to 1.5 by 0.1);
run;


/***************************************************************************************************/
/**************************************/
/* Step 3: Apply different PS methods */
/**************************************/
/***************************************************************************************************/
/*Method 1:Covariate adjustment using PS*/
proc logistic data=sas.Sample_ps;
   class EXPOSE; 
   model MACE_OUTCOME = EXPOSE denom;
run;
/*Covariate adjustment using PS: OR 0.824(0.709-0.956)*/
