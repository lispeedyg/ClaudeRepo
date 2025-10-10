-- ========================================================================
-- DIAGNOSTIC SCRIPT: Check Setup Operation Status for Specific Job
-- Purpose: Verify actual Status codes vs display labels for SM SETUPM
-- ========================================================================

-- Replace 'ENGRELEASE' with your actual Job number if different
DECLARE @WorkCenter VARCHAR(50) = 'ENGRELEASE'  -- From your screenshot

-- PART 1: Check the actual Status value for SM SETUPM operation
SELECT 
    'SETUP OPERATION CHECK' AS CheckType,
    j.Job,
    j.Customer,
    j.Part_Number,
    j.Status AS Job_Status,
    jo.Job_Operation,
    jo.Work_Center,
    jo.Operation_Service,
    jo.Description,
    jo.Status AS Operation_Status_Code,  -- This is the ACTUAL database value
    jo.Actual_Start,
    jo.Actual_Finish,
    -- Decode the status to see what it means
    CASE jo.Status
        WHEN 'O' THEN 'Open'
        WHEN 'R' THEN 'Ready'
        WHEN 'S' THEN 'Started'
        WHEN 'C' THEN 'Complete'
        WHEN 'H' THEN 'On Hold'
        ELSE jo.Status
    END AS Status_Meaning,
    -- Check if it should be considered complete
    CASE 
        WHEN jo.Status IN ('C', 'Complete', 'Closed') THEN '✓ Properly Closed'
        WHEN jo.Status = 'S' AND jo.Actual_Start IS NOT NULL THEN '⚠ Started but NOT Complete'
        WHEN jo.Status = 'O' THEN '⚠ Still Open'
        ELSE '⚠ Unexpected Status'
    END AS Needs_Cleanup
FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
WHERE jo.Work_Center = 'SM SETUPM'
    AND EXISTS (
        SELECT 1 FROM THURO.dbo.Job_Operation jo_main
        WHERE jo_main.Job = j.Job 
        AND jo_main.Work_Center = @WorkCenter
    )
ORDER BY j.Job DESC, jo.Operation_Service

-- PART 2: Check time entries for this setup operation
SELECT 
    'TIME ENTRIES CHECK' AS CheckType,
    j.Job,
    jo.Operation_Service,
    jo.Description,
    jot.Employee,
    e.First_Name + ' ' + e.Last_Name AS Operator_Name,
    jot.Work_Date,
    jot.Last_Updated,
    jot.Act_Run_Hrs,
    jot.Act_Run_Qty,
    jot.Operation_Complete,
    -- Check if time entry marked as complete
    CASE 
        WHEN jot.Operation_Complete = 1 THEN '✓ Marked Complete in Time Entry'
        ELSE '⚠ NOT marked complete in Time Entry'
    END AS Time_Entry_Status
FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
    INNER JOIN THURO.dbo.Employee e ON jot.Employee = e.Employee
WHERE jo.Work_Center = 'SM SETUPM'
    AND EXISTS (
        SELECT 1 FROM THURO.dbo.Job_Operation jo_main
        WHERE jo_main.Job = j.Job 
        AND jo_main.Work_Center = @WorkCenter
    )
    AND jot.Work_Date >= DATEADD(DAY, -90, GETDATE())
ORDER BY j.Job DESC, jot.Work_Date DESC

-- PART 3: Check production operations to see if they're active
SELECT 
    'PRODUCTION STATUS CHECK' AS CheckType,
    j.Job,
    jo.Operation_Service,
    jo.Description,
    jo.Work_Center,
    jo.Status AS Operation_Status_Code,
    CASE jo.Status
        WHEN 'O' THEN 'Open'
        WHEN 'R' THEN 'Ready'
        WHEN 'S' THEN 'Started'
        WHEN 'C' THEN 'Complete'
        ELSE jo.Status
    END AS Status_Meaning,
    MAX(jot.Work_Date) AS Last_Production_Date,
    MAX(jot.Last_Updated) AS Last_Updated,
    SUM(jot.Act_Run_Qty) AS Total_Qty_Produced,
    -- Key question: Is production happening but setup still open?
    CASE 
        WHEN jo.Status = 'C' THEN '✓ Production Complete'
        WHEN MAX(jot.Work_Date) >= DATEADD(DAY, -7, GETDATE()) THEN '→ ACTIVE PRODUCTION'
        WHEN MAX(jot.Work_Date) >= DATEADD(DAY, -30, GETDATE()) THEN '→ Recent Production'
        ELSE '→ Old/Inactive'
    END AS Production_Activity
FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    LEFT JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
WHERE jo.Work_Center = @WorkCenter
    AND jo.Work_Center != 'SM SETUPM'
GROUP BY j.Job, jo.Operation_Service, jo.Description, jo.Work_Center, jo.Status
ORDER BY j.Job DESC, jo.Operation_Service

-- PART 4: Summary - Does this setup need cleanup?
SELECT 
    'CLEANUP RECOMMENDATION' AS CheckType,
    j.Job,
    j.Customer,
    j.Part_Number,
    setup_op.Status AS Setup_Status_Code,
    CASE setup_op.Status
        WHEN 'O' THEN 'Open'
        WHEN 'R' THEN 'Ready'
        WHEN 'S' THEN 'Started'
        WHEN 'C' THEN 'Complete'
        ELSE setup_op.Status
    END AS Setup_Status_Meaning,
    prod_op.Status AS Production_Status_Code,
    CASE prod_op.Status
        WHEN 'O' THEN 'Open'
        WHEN 'R' THEN 'Ready'
        WHEN 'S' THEN 'Started'
        WHEN 'C' THEN 'Complete'
        ELSE prod_op.Status
    END AS Production_Status_Meaning,
    DATEDIFF(DAY, setup_op.Actual_Start, GETDATE()) AS Days_Since_Setup_Started,
    -- The verdict
    CASE 
        WHEN setup_op.Status IN ('C', 'Complete', 'Closed') 
            AND prod_op.Status IN ('C', 'Complete', 'Closed')
        THEN '✓ NO CLEANUP NEEDED - Both operations properly closed'
        
        WHEN setup_op.Status NOT IN ('C', 'Complete', 'Closed') 
            AND prod_op.Status IN ('C', 'Complete', 'Closed')
        THEN '⚠ CLEANUP NEEDED - Production complete but setup still open'
        
        WHEN setup_op.Status NOT IN ('C', 'Complete', 'Closed') 
            AND prod_op.Status NOT IN ('C', 'Complete', 'Closed')
        THEN '→ ACTIVE JOB - Setup and production both open (OK if job is running)'
        
        ELSE '? INVESTIGATE - Unexpected status combination'
    END AS Recommendation,
    -- What to do
    CASE 
        WHEN setup_op.Status NOT IN ('C', 'Complete', 'Closed') 
            AND prod_op.Status IN ('C', 'Complete', 'Closed')
        THEN 'ACTION: Close the SM SETUPM operation (005) by setting Status to Complete'
        
        WHEN setup_op.Status = 'S'
        THEN 'ACTION: Change operation Status from Started (S) to Complete (C)'
        
        ELSE 'NO ACTION NEEDED'
    END AS Action_Required
FROM THURO.dbo.Job j
    LEFT JOIN THURO.dbo.Job_Operation setup_op ON j.Job = setup_op.Job AND setup_op.Work_Center = 'SM SETUPM'
    LEFT JOIN THURO.dbo.Job_Operation prod_op ON j.Job = prod_op.Job AND prod_op.Work_Center = @WorkCenter
WHERE EXISTS (
        SELECT 1 FROM THURO.dbo.Job_Operation jo_check
        WHERE jo_check.Job = j.Job 
        AND jo_check.Work_Center = @WorkCenter
    )
ORDER BY j.Job DESC

-- ========================================================================
-- HOW TO USE THIS SCRIPT:
-- 1. Change @WorkCenter to match the machine from your screenshot (default is 'ENGRELEASE')
-- 2. Run all 4 parts
-- 3. Look at the CLEANUP RECOMMENDATION section (Part 4) for the verdict
-- 4. If it shows "CLEANUP NEEDED", the Action_Required column tells you what to do
-- ========================================================================
