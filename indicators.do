*Script to prepare 8 consistent indicators to measure deprivation in STEP data**
*v.1 20170412
*ssc install mdesc   //please install mdesc
*original data downloaded from http://www.icpsr.umich.edu/icpsrweb/NACDA/studies/31381
version 14.2
clear
set more off
clear matrix
clear mata
cap log close
global path "C:\STEP"
global path "\\qeh7\staff$\gree1598\STEP\"
global raw "$path\raw_data"
global temp "$path\temp_data"
global output "$path\output_data"

log using "$output\indicators.log", replace
set obs 1
gen var1=.
save "$output\summary", replace
clear

forvalues d=1(2)7 {
	*Information on nutrition for individuals of the same country
	local e= `d' + 1
	use "$raw\\DS000`e'\31381-000`e'-Data", clear
	*Q0002 or household ID number will be used to merge data, we create a variable that contains the number of observations per household
	bys Q0002 : egen obs_members = max(Q1007)
	
	*Assuming that this is the correct statistic to measure nutrition for 18 years and older
	gen bmi = Q2507 / (Q2506^2)  
	*Generate underweight and sunderweight as deprivations 
	gen underweight = (bmi < 18.5) if bmi != . 
	gen sunderweight = (bmi < 17) if bmi != . 
	gen overweight = (bmi > 25) if bmi != . 
	gen soverweight = (bmi > 30) if bmi != . 
	
	*The deprivation that is homogenised as d_nutrition is an adult in the household that is underweight.
	bys Q0002 : egen d_nutrition = max(underweight)
	bys Q0002 : egen d_nutrition_count = count(underweight==1)

	*Keep only nutrition data at household level
	keep Q0002 d_nutrition d_nutrition_count obs_members 
	duplicates drop Q0002, force
	save "$temp\\31381-000`d'-nutrition", replace
	
	*Call household level data to complete deprivations 
	use "$raw\\DS000`d'\31381-000`d'-Data", clear

	*Merge using HH ID
	*As Indian dataset has duplicates in terms of household, we first drop repeated observations identified in Q0002FLAG==0 ONLY for repeated observations
	if Q0001 == 106 {
		duplicates tag Q0002, gen(temp)
		drop if Q0002FLAG==0 & temp != 0
		duplicates report Q0002
		drop temp
		}
	merge 1:1 Q0002 using "$temp\\31381-000`d'-nutrition", assert(match master)
	drop _merge
*	erase "$temp\\31381-000`d'-nutrition"
	
	*Declare the complex survey design
	svyset Q0101B [pw=HHWEIGHT], strata(STRATA) singleunit(center)

	*Information on country is available at Q0001
	*Household size is available in variable Q0401
	*Local z captures the maximum number of columns in the dataset
	lookfor column
	gen temp=r(varlist)
	gen b=substr(temp,-2,2)
	local z=b
	drop temp
	*Using z, the following loop codes ages and educational level per member so they can be manipulated
	forvalues i=1/`z' {
		if `i' < 10 {
			clonevar age_`i' = Q0407_0`i' if Q0407_0`i' >= 0 
			gen primary_`i' = (Q0409_0`i' > 1) if Q0409_0`i' != .
		}
		if `i' > 10 {
			clonevar age_`i' = Q0407_`i' if Q0407_`i' >= 0 
			gen primary_`i' = (Q0409_`i' > 1) if Q0409_`i' != .
			}
	}

	*Create a variable that defines the number of people with primary or higher educational level per household
	egen hh_primary = rowtotal(primary_*), missing
	*Create a variable that states 1 for deprivation of primary level for all members of household 
	gen d_primary = cond(hh_primary==0,1,0) if hh_primary!=.

	/*this version 1 does not have code for missing restriction of 2/3 of households
	egen hh_edumiss = rowmiss(primary_*)*/

	*Variable that states 1 for deprivation in electricity
	recode Q0704 (2=1) (1=0), gen(d_electricity)

	*Variable that states 1 for deprivation in toilet (non-improved or shared)
	recode Q0508 (1/7=0) (8 = 1) (9 = 0) (10/87 = 1), gen(d_toilet)
	replace d_toilet = 1 if Q0509 == 1

	*Variable that states 1 for deprivation in sanitation (non-improved or further than 30mins away)
	recode Q0506 (1/5=0) (6 = 1) (7 = 0) (8 = 1) (9/10 = 0) (13/87 = 1), gen(d_water)
	replace d_water = 1 if Q0507 >= 30 & Q0507 < .

	*Variable that states 1 for deprivation in floor (earth floor)
	recode Q0504 (2=1) (1=0) (8 = .), gen(d_floor)

	*Variable that states 1 for deprivation in solid cooking fuel 
	recode Q0510 (1/3 = 0) (4/8 = 1) (87 = 0), gen(d_fuel)

	*Variables that states 1 for presence of small assets and car
	recode Q0715 (2=0), gen(radio)
	recode Q0701 (0=0)(nonmissing=1), gen(television)
	recode Q0711 (2=0) , gen(telephone)
	recode Q0712 (2=0), gen(mobile)
	recode Q0710 (2=0), gen(refrigerator)
	recode Q0703 (0=0) (-8=.) (nonmissing=1), gen(car)
	recode Q0705 (2=0), gen(bicycle)

	*Variable small add the total number of small assets per households
	egen small = rowtotal(radio television telephone mobile refrigerator bicycle), missing

	*Variable that states 1 for deprivation in assets (less than 2 small assets and abscense of car)
	gen d_assets = cond(small>1|car==1,0,1) if small!=. & car!=.

	*Descriptives of the variables created
	mdesc d_primary d_electricity d_toilet d_water d_floor d_fuel d_assets radio television telephone mobile refrigerator bicycle car small 
	sum d_primary d_electricity d_toilet d_water d_floor d_fuel d_assets radio television telephone mobile refrigerator bicycle car small 

	*The sample for assessing 7 deprivations is based on those without missing information in any indicator
	gen sample = !missing(d_primary, d_electricity, d_toilet, d_water, d_floor, d_fuel, d_assets)

	*List of 7 deprivations assessed
	local cv d_primary d_electricity d_toilet d_water d_floor d_fuel d_assets

	*Variable that counts the number of deprivations experienced
	egen counting_vector = rowtotal(`cv') if sample==1

	*Loop that generates the censored and raw headcount ratios of each deprivation
	foreach var in `cv' {
		svy: mean `var' if sample==1
		gen R`var'=_b[`var'] 
			forvalues x=0(1)10 {
				gen ch`var'_`x' = ((counting_vector>=`x') & `var'==1) if sample==1
				svy: mean ch`var'_`x' if sample==1
				gen CH`var'_`x'=_b[ch`var'_`x'] 
			}
		}

	*Loop that generates the proportion of people experiencing r deprivations 
	svy: proportion counting_vector if sample==1
	forvalues r=0/7 {
		cap gen Dc`r'=_b[counting_vector:`r']
	}

	*Loop that generates the proportion of people experiencing j and more deprivations
	forvalues j=0(1)7 {
	gen hc`j' = (counting_vector>=`j') if sample==1
	qui svy: mean hc`j' if sample==1
	gen Hc`j'=_b[hc`j'] 
	}
	*Loop that generates the proportion of people in sample living in urban and rural areas
	recode Q0104 (2=0), gen(urban)
	gen temp=1
	sum urb
	local f=r(max)
	svy: proportion urban if sample==1, over(temp)
	forvalues d=1(1)`f' {
		gen ps`d'=_b[_prop_`d':1]
	}
	*Loop that generates the proportion of people experiencing j and more deprivations in urban and rural areas
	forvalues j=1/7 {
		svy: mean hc`j' if sample==1, over(urban)
			forvalues g=1(1)`f' {
				cap gen dp_`j'_`g'=_b[`g']
				}
		}
	*Keep a couple of lines per country
				duplicates drop urban, force
	*Keep the variables of interest
	keep Q0001 Q0104 R* CH* Hc* Dc* ps* dp*
	append using "$output\summary.dta"
	save "$output\summary.dta", replace
}

*Sequence repeated for the last two datasets 
foreach d in 09 11 {
	*Information on nutrition for individuals of the same country
	local e= `d' + 1
	use "$raw\\DS00`e'\31381-00`e'-Data", clear
	*Q0002 or household ID number will be used to merge data, we create a variable that contains the number of observations per household
	bys Q0002 : egen obs_members = max(Q1007)
	
	*Assuming that this is the correct statistic to measure nutrition for 18 years and older
	gen bmi = Q2507 / (Q2506^2)  
	*Generate underweight and sunderweight as deprivations 
	gen underweight = (bmi < 18.5) if bmi != . 
	gen sunderweight = (bmi < 17) if bmi != . 
	gen overweight = (bmi > 25) if bmi != . 
	gen soverweight = (bmi > 30) if bmi != . 
	
	*The deprivation that is homogenised as d_nutrition is an adult in the household that is underweight.
	bys Q0002 : egen d_nutrition = max(underweight)
	bys Q0002 : egen d_nutrition_count = count(underweight==1)

	*Keep only nutrition data at household level
	keep Q0002 d_nutrition d_nutrition_count obs_members 
	duplicates drop Q0002, force
	save "$temp\\31381-00`d'-nutrition", replace
	
	*Call household level data to complete deprivations 
	use "$raw\\DS00`d'\31381-00`d'-Data", clear

	*Merge using HH ID
	*As Indian dataset has duplicates in terms of household, we first drop repeated observations identified in Q0002FLAG==0 ONLY for repeated observations
	if Q0001 == 106 {
		duplicates tag Q0002, gen(temp)
		drop if Q0002FLAG==0 & temp != 0
		duplicates report Q0002
		drop temp
		}
	merge 1:1 Q0002 using "$temp\\31381-00`d'-nutrition", assert(match master)
	drop _merge
*	erase "$temp\\31381-000`d'-nutrition"
	
	*Declare the complex survey design
	svyset Q0101B [pw=HHWEIGHT], strata(STRATA) singleunit(center)

	*Information on country is available at Q0001
	*Household size is available in variable Q0401
	*Local z captures the maximum number of columns in the dataset
	lookfor column
	gen temp=r(varlist)
	tostring temp, replace
	if temp != "." {
		gen b=substr(temp,-2,2)
		local z=b
		}
	else { 
		local z=25
	}
		drop temp
	*Using z, the following loop codes ages and educational level per member so they can be manipulated
	forvalues i=1/`z' {
		if `i' < 10 {
			clonevar age_`i' = Q0407_0`i' if Q0407_0`i' >= 0 
			gen primary_`i' = (Q0409_0`i' > 1) if Q0409_0`i' != .
		}
		if `i' > 10 {
			clonevar age_`i' = Q0407_`i' if Q0407_`i' >= 0 
			gen primary_`i' = (Q0409_`i' > 1) if Q0409_`i' != .
			}
	}

	*Create a variable that defines the number of people with primary or higher educational level per household
	egen hh_primary = rowtotal(primary_*), missing
	*Create a variable that states 1 for deprivation of primary level for all members of household 
	gen d_primary = cond(hh_primary==0,1,0) if hh_primary!=.

	/*this version 1 does not have code for missing restriction of 2/3 of households
	egen hh_edumiss = rowmiss(primary_*)*/

	*Variable that states 1 for deprivation in electricity
	recode Q0704 (2=1) (1=0), gen(d_electricity)

	*Variable that states 1 for deprivation in toilet (non-improved or shared)
	recode Q0508 (1/7=0) (8 = 1) (9 = 0) (10/87 = 1), gen(d_toilet)
	replace d_toilet = 1 if Q0509 == 1

	*Variable that states 1 for deprivation in sanitation (non-improved or further than 30mins away)
	recode Q0506 (1/5=0) (6 = 1) (7 = 0) (8 = 1) (9/10 = 0) (13/87 = 1), gen(d_water)
	replace d_water = 1 if Q0507 >= 30 & Q0507 < .

	*Variable that states 1 for deprivation in floor (earth floor)
	recode Q0504 (2=1) (1=0) (8 = .), gen(d_floor)

	*Variable that states 1 for deprivation in solid cooking fuel 
	recode Q0510 (1/3 = 0) (4/8 = 1) (87 = 0), gen(d_fuel)

	*Variables that states 1 for presence of small assets and car
	recode Q0715 (2=0), gen(radio)
	recode Q0701 (0=0)(nonmissing=1), gen(television)
	recode Q0711 (2=0) , gen(telephone)
	recode Q0712 (2=0), gen(mobile)
	recode Q0710 (2=0), gen(refrigerator)
	recode Q0703 (0=0) (-8=.) (nonmissing=1), gen(car)
	recode Q0705 (2=0), gen(bicycle)

	*Variable small add the total number of small assets per households
	egen small = rowtotal(radio television telephone mobile refrigerator bicycle), missing

	*Variable that states 1 for deprivation in assets (less than 2 small assets and abscense of car)
	gen d_assets = cond(small>1|car==1,0,1) if small!=. & car!=.

	*Descriptives of the variables created
	mdesc d_primary d_electricity d_toilet d_water d_floor d_fuel d_assets radio television telephone mobile refrigerator bicycle car small 
	sum d_primary d_electricity d_toilet d_water d_floor d_fuel d_assets radio television telephone mobile refrigerator bicycle car small 

	*The sample for assessing 7 deprivations is based on those without missing information in any indicator
	gen sample = !missing(d_primary, d_electricity, d_toilet, d_water, d_floor, d_fuel, d_assets)

	*List of 7 deprivations assessed
	local cv d_primary d_electricity d_toilet d_water d_floor d_fuel d_assets

	*Variable that counts the number of deprivations experienced
	egen counting_vector = rowtotal(`cv') if sample==1

	*Loop that generates the censored and raw headcount ratios of each deprivation
	foreach var in `cv' {
		svy: mean `var' if sample==1
		gen R`var'=_b[`var'] 
			forvalues x=0(1)10 {
				gen ch`var'_`x' = ((counting_vector>=`x') & `var'==1) if sample==1
				svy: mean ch`var'_`x' if sample==1
				gen CH`var'_`x'=_b[ch`var'_`x'] 
			}
		}

	*Loop that generates the proportion of people experiencing r deprivations 
	svy: proportion counting_vector if sample==1
	forvalues r=0/7 {
		cap gen Dc`r'=_b[counting_vector:`r']
	}

	*Loop that generates the proportion of people experiencing j and more deprivations
	forvalues j=0(1)7 {
	gen hc`j' = (counting_vector>=`j') if sample==1
	qui svy: mean hc`j' if sample==1
	gen Hc`j'=_b[hc`j'] 
	}
	*Loop that generates the proportion of people in sample living in urban and rural areas
	recode Q0104 (2=0), gen(urban)
	gen temp=1
	sum urb
	local f=r(max)
	svy: proportion urban if sample==1, over(temp)
	forvalues d=1(1)`f' {
		gen ps`d'=_b[_prop_`d':1]
	}
	*Loop that generates the proportion of people experiencing j and more deprivations in urban and rural areas
	forvalues j=1/7 {
		svy: mean hc`j' if sample==1, over(urban)
			forvalues g=1(1)`f' {
				cap gen dp_`j'_`g'=_b[`g']
				}
		}
	*Keep a couple of lines per country
				duplicates drop urban, force
	*Keep the variables of interest
	keep Q0001 Q0104 R* CH* Hc* Dc* ps* dp*
	append using "$output\summary.dta"
	save "$output\summary.dta", replace
}
