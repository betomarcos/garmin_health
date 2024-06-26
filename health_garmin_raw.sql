-- Create table "health_log" from a csv export from Google sheets. 
-- Data is a manual daily log about health metrics I want to track. 
-- Loaded the csv data using the MySQL Data Import Wizard.
-- After simple EDA on garmin.health_log, then I loaded Garmin health metrics (HR, HRV, Sleep score, etc) to then join with manual log.


CREATE TABLE garmin.health_log (
    date DATE,
    day_text VARCHAR(20),
    coffee_ct INT,
    alcohol_ct INT,
    allergies_score DECIMAL(5,2),
    zyrtec_ct INT,
    flonase_ct INT,
    sick_score DECIMAL(5,2),
    hangover_score DECIMAL(5,2),
    outdoors INT,
    socialized INT,
    meditated INT,
    mood_score DECIMAL(5,2),
    productivity_score DECIMAL(5,2),
    work_stress_score DECIMAL(5,2)
);

select * from health_log_raw;

-- see which day of the week I consume more coffee or alcohol
select day_text, sum(coffee_ct), sum(alcohol_ct)
from health_log_raw
group by day_text;

-- see which day of the week I am have better mood, or when I have more stress
select day_text, avg(mood_score), avg(work_stress_score)
from health_log_raw
group by day_text;

-- see which day of the week I socialize, or go outdoors the most
select day_text, sum(outdoors), sum(socialized)
from health_log_raw
group by day_text;



-- Create 2 more tables, Load data (using Data Import Wizard) from Garmin health metrics (HR, HRV, Sleep score, etc) to then join with manual log.

CREATE TABLE garmin.garmin_sleep_raw (
    Date DATE,
    Score DECIMAL(5,2),
    Quality VARCHAR(20),
    Duration VARCHAR(20),
    Sleep_Need VARCHAR(20),
    Bedtime TIME,
    Wake_Time TIME
);

CREATE TABLE garmin.garmin_hr_raw (
    Date DATE,
    Resting VARCHAR(20),
    High VARCHAR(20)
);

-- EDA on the new 2 tables:
select * from garmin.garmin_sleep_raw;
select * from garmin.garmin_hr_raw;

-- see avg min max from resting HR
select dayname(Date) as day, round(avg(resting), 1) as avg, min(resting) as min, max(resting) as max, (max(resting)-min(resting)) as dif
from garmin.garmin_hr_raw
group by 1;




-- create a new table that joins most important metrics per day

select *
from garmin.health_log_raw hl
left join garmin.garmin_sleep_raw s on hl.date = s.date
left join garmin.garmin_hr_raw hr on hl.date = hr.date
order by hl.date asc;

select 
	hl.*
    , s.Score as sleep_score
    , s.Duration as sleep_duration
    , s.Bedtime as sleep_bedtime
    , s.Wake_time as sleep_waketime
    , hr.Resting as resting_hr
    , hr.High as max_hr
from garmin.health_log_raw hl
left join garmin.garmin_sleep_raw s on hl.date = s.date
left join garmin.garmin_hr_raw hr on hl.date = hr.date
order by hl.date asc;

-- Create a stage table based on the query with all the necessary data

CREATE TABLE garmin.stage_table AS
SELECT 
    hl.*,
    s.Score AS sleep_score,
    s.Duration AS sleep_duration,
    s.Bedtime AS sleep_bedtime,
    s.Wake_Time AS sleep_waketime,
    hr.Resting AS resting_hr,
    hr.High AS max_hr
FROM
    garmin.health_log_raw hl
        LEFT JOIN garmin.garmin_sleep_raw s ON hl.date = s.Date
        LEFT JOIN garmin.garmin_hr_raw hr ON hl.date = hr.Date
ORDER BY hl.date ASC;


select * from garmin.stage_table;


-- now clean up the stage_table.
-- the sleep_duration would be more usable if we had number of minutes, instead of the "8h 01m" format it currently is. 
-- However, we can extract that from sleep_bedtime-sleep_waketime.
-- Afterwards, discovered that "Sleep Duration" a native field ffrom Garmin, means the actual duration of sleeping time, not necesarily the difference between bedtime and wake time.


select 
	sleep_bedtime
    , sleep_waketime
    , sleep_duration
    , TIMESTAMPDIFF(SECOND, sleep_bedtime, sleep_waketime) / 60 / 60 AS sleep_duration_minutes
from garmin.stage_table
limit 10;

-- will split "sleep_duration" into hours an dminutes


select *, ((hours * 60) + minutes) as sleep_minutes
from (
select 
	`date`
    , sleep_duration
    , SUBSTRING_INDEX(sleep_duration, 'h', 1) AS hours
    , SUBSTRING_INDEX(SUBSTRING_INDEX(sleep_duration, 'h', -1), 'm', 1) AS minutes
from garmin.stage_table
limit 5
) as newtable;


select
 ((SUBSTRING_INDEX(sleep_duration, 'h', 1)*60) +  SUBSTRING_INDEX(SUBSTRING_INDEX(sleep_duration, 'h', -1), 'm', 1)) AS sleep_minutes
from garmin.stage_table
limit 5;

 
-- create new field, and insert the "sleep_minutes" new calculated column and data to the stage_table
ALTER TABLE garmin.stage_table ADD COLUMN sleep_minutes INT;
UPDATE stage_table SET sleep_minutes =  ((SUBSTRING_INDEX(sleep_duration, 'h', 1)*60) +  SUBSTRING_INDEX(SUBSTRING_INDEX(sleep_duration, 'h', -1), 'm', 1));
select * from garmin.stage_table;

-- create new field to insert a "sleep_hours" to stage_table
ALTER TABLE garmin.stage_table ADD COLUMN sleep_hours DECIMAL(5,2);
UPDATE stage_table SET sleep_hours = round(sleep_minutes/60, 2);


-- data is ready. Now from stage_table create a PROD table. This way we can keep editing Stage_table if needed, but Prod is used for analysis.

CREATE TABLE garmin.prod_table AS
SELECT * FROM stage_table 
ORDER BY date ASC;

select * from garmin.prod_table;






------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------
/* 
Next step, create a script / stored procedure for the ETL process.
- given the RAW tables are created and reloaded manually using the import wizard, 
we only need to update the stage and prod tables running the etl scripts.
- run the MySQL Data Import Wizard to reload the RAW tables.
- Run the stage_table script
- Run the prod_table script
*/ 
    
-- Step 1: run the MySQL Data Import Wizard to reload the RAW tables. Ensure data types are accurate
-- Step 2: drop the stage_table
	DROP TABLE garmin.stage_table;

-- Step 3: recreate the stage_table    
	CREATE TABLE garmin.stage_table AS
	SELECT 
		hl.*,
		s.Score AS sleep_score,
		s.Duration AS sleep_duration,
		s.Bedtime AS sleep_bedtime,
		s.Wake_Time AS sleep_waketime,
		hr.Resting AS resting_hr,
		hr.High AS max_hr
	FROM garmin.health_log_raw hl
			LEFT JOIN garmin.garmin_sleep_raw s ON hl.date = s.Date
			LEFT JOIN garmin.garmin_hr_raw hr ON hl.date = hr.Date
	ORDER BY hl.date ASC;

-- Step 4: run 2 alter tables to add 2 fields to stage_table
	ALTER TABLE garmin.stage_table ADD COLUMN sleep_minutes INT;
	UPDATE stage_table SET sleep_minutes =  ((SUBSTRING_INDEX(sleep_duration, 'h', 1)*60) +  SUBSTRING_INDEX(SUBSTRING_INDEX(sleep_duration, 'h', -1), 'm', 1));

	ALTER TABLE garmin.stage_table ADD COLUMN sleep_hours DECIMAL(5,2);
	UPDATE stage_table SET sleep_hours = round(sleep_minutes/60, 2);

-- Step 5: drop the prod_table
	DROP TABLE garmin.prod_table;

-- Step 6: recreate the prod_table 
	CREATE TABLE garmin.prod_table AS SELECT * FROM stage_table ORDER BY date ASC;
    
-- Step 7: review prod_table
	SELECT * FROM garmin.prod_table limit 50;
    
-- Step 8: process is completed. Data can be analized and visualized.

