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
/*Method 4-1: Standardized mortality ratio weighting (SMRW)*/
data Final_dataset_ps_smrw;
	set sas.Sample_ps;
	if EXPOSE=1 then smrw=1; else if EXPOSE=0 then smrw=denom/(1-denom);
run;


proc means data = Final_dataset_ps_smrw min p5 median mean p95 std max;
	var smrw;
run;


*** Truncate weights at the 1st and 99th percentile ***;
*Extract 1st and 99th percentile of SMR weights;
proc univariate data = Final_dataset_ps_smrw noprint;
	var smrw;
	output out=pctl pctlpts=1 99 pctlpre=p;
run;

* Save 1st, 99th percentile cutoff;
data temp3;
	set pctl;
	call symput ('cutoff_smrw_99', p99);
	call symput ('cutoff_smrw_1', p1);
run;


*Truncate weights at the 1st and 99th percentile;
data Final_dataset_ps_smrw_1_99;
	set Final_dataset_ps_smrw;
	smrw_p1_99 = smrw;
	if smrw_p1_99 > %sysevalf(&cutoff_smrw_99) then do;
		smrw_p1_99 = %sysevalf(&cutoff_smrw_99);
	end;
	else if smrw_p1_99 < %sysevalf(&cutoff_smrw_1) then do;
		smrw_p1_99 = %sysevalf(&cutoff_smrw_1);
	end;
run;


proc means data = Final_dataset_ps_smrw_1_99 min p5 median mean p95 std max;
	var smrw_p1_99;
run;


*** Fit logistic regression model with truncated weights ***;	
proc logistic data = Final_dataset_ps_smrw_1_99;
   	class EXPOSE(ref="0") MACE_OUTCOME(ref="0");
   	model MACE_OUTCOME = EXPOSE;
	weight smrw_p1_99;
run;
/*Standardized mortality ratio weighting: OR 0.830(0.720-0.958)*/
 
