-- ========================================================================
-- FIND ALL OPERATIONS FLAGGED FOR CLEANUP
-- Shows which machines/jobs have the ⚠ warning in the dashboard
-- ========================================================================

USE [THURO]
GO

-- Find all jobs with complete production operations but unclosed setup operations
SELECT 
    '⚠ CLEANUP NEEDED' AS Alert,
    w.Work_Center AS Machine,
    w.Department,
    j.Job,
    j.Customer,
    j.Part_Number,
    j.Status AS Job_Status,
    
    -- Production Operation Info
    prod_op.Operation_Service AS Prod_Operation,
    prod_op.Description AS Prod_Description,
    prod_op.Status AS Prod_Status_Code,
    CASE prod_op.Status
        WHEN 'C' THEN 'Complete'
        WHEN 'S' THEN 'Started'
        WHEN 'O' THEN 'Open'
        WHEN 'R' THEN 'Ready'
        ELSE prod_op.Status
    END AS Prod_Status_Meaning,
    
    -- Setup Operation Info (THE PROBLEM)
    setup_op.Job_Operation AS Setup_Job_Operation,
    setup_op.Operation_Service AS Setup_Operation,
    setup_op.Status AS Setup_Status_Code,
    CASE setup_op.Status
        WHEN 'C' THEN 'Complete'
        WHEN 'S' THEN 'Started'
        WHEN 'O' THEN 'Open'
        WHEN 'R' THEN 'Ready'
        ELSE setup_op.Status
    END AS Setup_Status_Meaning,
    setup_op.Actual_Start AS Setup_Started_Date,
    DATEDIFF(DAY, setup_op.Actual_Start, GETDATE()) AS Days_Setup_Open,
    
    -- Setup Operator Info
    setup_time.setup_operator AS Setup_Operator,
    setup_time.setup_hours AS Setup_Hours,
    
    -- Last Production Activity
    last_prod.Last_Work_Date AS Last_Production_Date,
    DATEDIFF(DAY, last_prod.Last_Work_Date, GETDATE()) AS Days_Since_Production,
    
    -- What you'll see in the dashboard
    CONCAT('⚠ CLEANUP: Setup ', setup_time.setup_operator, ' still open from SM-', 
           CAST(ISNULL(setup_time.setup_hours, 0) AS VARCHAR), 'h') AS Dashboard_Message,
    
    -- Recommendation
    CASE 
        WHEN setup_op.Status = 'S' THEN 'Change Setup Status from Started to Complete'
        WHEN setup_op.Status = 'O' THEN 'Change Setup Status from Open to Complete'
        WHEN setup_op.Status = 'R' THEN 'Change Setup Status from Ready to Complete'
        ELSE 'Set Setup Status to Complete'
    END AS Action_Required,
    
    -- How to fix it in JobBoss
    CONCAT('Job: ', j.Job, ' → Routing Tab → Operation ', setup_op.Operation_Service, 
           ' (SM SETUPM) → Change Status to Complete') AS How_To_Fix

FROM THURO.dbo.Job j with (NoLock)
    
    -- Find jobs with COMPLETE production operations
    INNER JOIN (
        SELECT 
            jo.Job, 
            jo.Work_Center,
            jo.Operation_Service,
            jo.Description,
            jo.Status,
            jo.Job_Operation,
            ROW_NUMBER() OVER (
                PARTITION BY jo.Job, jo.Work_Center 
                ORDER BY 
                    CASE WHEN jo.Status IN ('Complete', 'Closed', 'C') THEN 1 ELSE 0 END DESC,
                    jo.Sequence DESC
            ) AS rn
        FROM THURO.dbo.Job_Operation jo with (NoLock)
        WHERE jo.Status IN ('Complete', 'Closed', 'C')  -- Production is complete
            AND jo.Work_Center != 'SM SETUPM'
    ) prod_op ON prod_op.Job = j.Job AND prod_op.rn = 1
    
    -- Get the work center
    INNER JOIN THURO.dbo.Work_Center w with (NoLock) ON w.Work_Center = prod_op.Work_Center
    
    -- Find OPEN/UNCLOSED setup operations for these jobs
    INNER JOIN THURO.dbo.Job_Operation setup_op with (NoLock) 
        ON setup_op.Job = j.Job 
        AND setup_op.Work_Center = 'SM SETUPM'
        AND setup_op.Status NOT IN ('Complete', 'Closed', 'C')  -- Setup is NOT complete
    
    -- Get setup time and operator info
    LEFT JOIN (
        SELECT 
            jo_setup.Job,
            jo_setup.Job_Operation,
            SUM(jot_setup.Act_Run_Hrs) AS setup_hours,
            (SELECT TOP 1 
                UPPER(LEFT(e_setup.First_Name, 1)) + LOWER(SUBSTRING(e_setup.First_Name, 2, LEN(e_setup.First_Name))) + '_' + 
                UPPER(LEFT(e_setup.Last_Name, 1))
             FROM THURO.dbo.Job_Operation_Time jot_recent with (NoLock)
                INNER JOIN THURO.dbo.Employee e_setup with (NoLock) ON jot_recent.Employee = e_setup.Employee
             WHERE jot_recent.Job_Operation = jo_setup.Job_Operation
                AND jot_recent.Act_Run_Hrs > 0
                AND jot_recent.Work_Date >= DATEADD(DAY, -90, GETDATE())
             ORDER BY jot_recent.Work_Date DESC
            ) AS setup_operator
        FROM THURO.dbo.Job_Operation jo_setup with (NoLock)
            LEFT JOIN THURO.dbo.Job_Operation_Time jot_setup with (NoLock) 
                ON jo_setup.Job_Operation = jot_setup.Job_Operation
                AND jot_setup.Work_Date >= DATEADD(DAY, -90, GETDATE())
        WHERE jo_setup.Work_Center = 'SM SETUPM'
        GROUP BY jo_setup.Job, jo_setup.Job_Operation
    ) setup_time ON setup_time.Job_Operation = setup_op.Job_Operation
    
    -- Get last production activity
    LEFT JOIN (
        SELECT 
            jot.Job_Operation,
            MAX(jot.Work_Date) AS Last_Work_Date
        FROM THURO.dbo.Job_Operation_Time jot with (NoLock)
        WHERE jot.Work_Date >= DATEADD(DAY, -90, GETDATE())
        GROUP BY jot.Job_Operation
    ) last_prod ON last_prod.Job_Operation = prod_op.Job_Operation

WHERE 
    w.Department IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing')
    AND w.Status = 1 
    AND w.UVText1 = 'MStatusQry'

ORDER BY 
    Days_Setup_Open DESC,  -- Oldest problems first
    w.Work_Center,
    j.Job

-- ========================================================================
-- INTERPRETATION GUIDE:
-- 
-- This query finds jobs where:
--   ✓ Production operation is COMPLETE (Status = 'C')
--   ⚠ Setup operation is still OPEN/STARTED (Status = 'S', 'O', 'R')
-- 
-- These are the jobs causing the ⚠ CLEANUP warnings in your dashboard.
--
-- COLUMNS TO FOCUS ON:
-- - Machine: Which machine shows the warning
-- - Job: Which job number
-- - Setup_Status_Code: What the setup status is ('S' = Started is most common)
-- - Days_Setup_Open: How long it's been stuck open
-- - Setup_Operator: Who was working on setup
-- - Action_Required: What to change
-- - How_To_Fix: Step-by-step instructions
--
-- TO FIX IN JOBBOSS:
-- 1. Open the Job number shown
-- 2. Go to Routing tab
-- 3. Find the SM SETUPM operation (usually 005)
-- 4. Change Status from "Started" or "Open" to "Complete"
-- 5. Save
-- ========================================================================
