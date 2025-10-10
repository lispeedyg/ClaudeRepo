-- ========================================================================
-- SHOW ALL OPERATIONS FOR A SPECIFIC JOB - FIXED VERSION
-- Purpose: See complete routing status regardless of cleanup needs
-- ========================================================================

USE [THURO]
GO

-- Change this to your job number
DECLARE @JobNumber VARCHAR(50) = '1317620'

-- Show ALL operations for this job
SELECT 
    j.Job,
    j.Customer,
    j.Part_Number,
    j.Status AS Job_Status,
    j.Status_Date AS Job_Status_Date,
    '---' AS Separator1,
    
    -- Operation Details
    jo.Job_Operation,
    jo.Sequence,
    jo.Work_Center,
    jo.Operation_Service,
    jo.Description,
    jo.Status AS Op_Status_Code,
    
    -- Decode the status
    CASE jo.Status
        WHEN 'O' THEN 'Open'
        WHEN 'R' THEN 'Ready'
        WHEN 'S' THEN 'Started'
        WHEN 'C' THEN 'Complete'
        WHEN 'H' THEN 'On Hold'
        ELSE jo.Status
    END AS Op_Status_Meaning,
    
    jo.Actual_Start,
    jo.Est_Required_Qty,
    '---' AS Separator2,
    
    -- Time Entry Summary
    time_summary.Total_Hours,
    time_summary.Total_Qty_Produced,
    time_summary.Last_Work_Date,
    time_summary.Days_Since_Last_Work,
    time_summary.Latest_Operator,
    '---' AS Separator3,
    
    -- Status Check
    CASE 
        WHEN jo.Work_Center = 'SM SETUPM' AND jo.Status IN ('C', 'Complete', 'Closed')
        THEN '✓ Setup Complete'
        
        WHEN jo.Work_Center = 'SM SETUPM' AND jo.Status NOT IN ('C', 'Complete', 'Closed')
        THEN '⚠ Setup OPEN - Needs Closure'
        
        WHEN jo.Work_Center != 'SM SETUPM' AND jo.Status IN ('C', 'Complete', 'Closed')
        THEN '✓ Production Complete'
        
        WHEN jo.Work_Center != 'SM SETUPM' AND jo.Status = 'S'
        THEN '→ Production Started'
        
        WHEN jo.Work_Center != 'SM SETUPM' AND jo.Status = 'O'
        THEN '→ Production Open'
        
        ELSE 'Other Status'
    END AS Status_Check,
    
    -- What should be done?
    CASE 
        WHEN jo.Work_Center = 'SM SETUPM' 
             AND jo.Status NOT IN ('C', 'Complete', 'Closed')
             AND EXISTS (
                 SELECT 1 FROM THURO.dbo.Job_Operation jo_prod
                 WHERE jo_prod.Job = jo.Job
                   AND jo_prod.Work_Center != 'SM SETUPM'
                   AND jo_prod.Status IN ('C', 'Complete', 'Closed')
             )
        THEN '⚠ CLEANUP NEEDED: Close this setup operation'
        
        WHEN jo.Work_Center = 'SM SETUPM' 
             AND jo.Status NOT IN ('C', 'Complete', 'Closed')
        THEN '→ Setup still open (may be OK if production is active)'
        
        WHEN jo.Status IN ('C', 'Complete', 'Closed')
        THEN '✓ No action needed'
        
        ELSE 'Active operation'
    END AS Action_Needed

FROM THURO.dbo.Job j
    INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
    
    -- Get time entry summary
    LEFT JOIN (
        SELECT 
            jot.Job_Operation,
            SUM(jot.Act_Run_Hrs) AS Total_Hours,
            SUM(jot.Act_Run_Qty) AS Total_Qty_Produced,
            MAX(jot.Work_Date) AS Last_Work_Date,
            DATEDIFF(DAY, MAX(jot.Work_Date), GETDATE()) AS Days_Since_Last_Work,
            (SELECT TOP 1 
                UPPER(LEFT(e.First_Name, 1)) + LOWER(SUBSTRING(e.First_Name, 2, LEN(e.First_Name))) + '_' + 
                UPPER(LEFT(e.Last_Name, 1))
             FROM THURO.dbo.Job_Operation_Time jot_last
                INNER JOIN THURO.dbo.Employee e ON jot_last.Employee = e.Employee
             WHERE jot_last.Job_Operation = jot.Job_Operation
             ORDER BY jot_last.Work_Date DESC, jot_last.Last_Updated DESC
            ) AS Latest_Operator
        FROM THURO.dbo.Job_Operation_Time jot
        WHERE jot.Work_Date >= DATEADD(DAY, -365, GETDATE())
        GROUP BY jot.Job_Operation
    ) time_summary ON time_summary.Job_Operation = jo.Job_Operation

WHERE j.Job = @JobNumber

ORDER BY jo.Sequence, jo.Operation_Service

-- ========================================================================
-- SUMMARY: Will the dashboard show a cleanup warning?
-- ========================================================================
SELECT 
    @JobNumber AS Job_Being_Checked,
    CASE 
        WHEN EXISTS (
            -- Has complete production operation
            SELECT 1 FROM THURO.dbo.Job_Operation jo_prod
            WHERE jo_prod.Job = @JobNumber
              AND jo_prod.Status IN ('C', 'Complete', 'Closed')
              AND jo_prod.Work_Center != 'SM SETUPM'
        )
        AND EXISTS (
            -- Has OPEN setup operation
            SELECT 1 FROM THURO.dbo.Job_Operation jo_setup
            WHERE jo_setup.Job = @JobNumber
              AND jo_setup.Status NOT IN ('C', 'Complete', 'Closed')
              AND jo_setup.Work_Center = 'SM SETUPM'
        )
        THEN '⚠ YES - This job WILL show cleanup warning in dashboard'
        
        WHEN NOT EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo_setup
            WHERE jo_setup.Job = @JobNumber
              AND jo_setup.Work_Center = 'SM SETUPM'
        )
        THEN '○ NO - This job has no setup operation'
        
        WHEN NOT EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo_prod
            WHERE jo_prod.Job = @JobNumber
              AND jo_prod.Status IN ('C', 'Complete', 'Closed')
              AND jo_prod.Work_Center != 'SM SETUPM'
        )
        THEN '○ NO - Production is not complete yet'
        
        ELSE '✓ NO - Both setup and production are properly closed'
    END AS Will_Show_Cleanup_Warning,
    
    (SELECT COUNT(*) FROM THURO.dbo.Job_Operation 
     WHERE Job = @JobNumber AND Work_Center = 'SM SETUPM') AS Setup_Operations_Count,
    
    (SELECT COUNT(*) FROM THURO.dbo.Job_Operation 
     WHERE Job = @JobNumber AND Work_Center != 'SM SETUPM') AS Production_Operations_Count,
    
    -- Show the actual status codes we found
    (SELECT TOP 1 Status FROM THURO.dbo.Job_Operation 
     WHERE Job = @JobNumber AND Work_Center = 'SM SETUPM') AS Setup_Status,
    
    (SELECT TOP 1 Status FROM THURO.dbo.Job_Operation 
     WHERE Job = @JobNumber AND Work_Center != 'SM SETUPM' 
     ORDER BY Sequence DESC) AS Production_Status

-- ========================================================================
-- INSTRUCTIONS:
-- 1. Change @JobNumber at the top to your job (currently set to '1317620')
-- 2. Run the query
-- 3. Look at BOTH result sets:
--    - First table: Shows ALL operations and their status
--    - Second table: Shows if this job will trigger a cleanup warning
-- ========================================================================
