-- ========================================================================
-- FIRST RUN DIAGNOSTIC - Check Part Number History
-- Purpose: Determine why a part is marked as First Run (F) or Repeat (O)
-- ========================================================================

USE [THURO]
GO

-- Change this to the part number you want to check
DECLARE @PartNumber VARCHAR(50) = '858046-1'

-- ========================================================================
-- PART 1: Show ALL jobs for this part number (complete history)
-- ========================================================================
SELECT 
    'COMPLETE HISTORY' AS Section,
    j.Job,
    j.Part_Number,
    j.Status AS Job_Status,
    j.Status_Date,
    j.Customer,
    
    -- Check if this job has any production activity
    CASE 
        WHEN EXISTS (
            SELECT 1 FROM THURO.dbo.Job_Operation jo
            INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
            WHERE jo.Job = j.Job AND jot.Act_Run_Qty > 0
        ) THEN '✓ HAS PRODUCTION'
        ELSE '○ No Production Yet'
    END AS Has_Production,
    
    -- Total quantity produced across all operations
    (SELECT ISNULL(SUM(jot.Act_Run_Qty), 0)
     FROM THURO.dbo.Job_Operation jo
     INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
     WHERE jo.Job = j.Job
    ) AS Total_Parts_Produced,
    
    -- When was production done?
    (SELECT MAX(jot.Work_Date)
     FROM THURO.dbo.Job_Operation jo
     INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
     WHERE jo.Job = j.Job AND jot.Act_Run_Qty > 0
    ) AS Last_Production_Date,
    
    -- Job sequence indicator
    ROW_NUMBER() OVER (ORDER BY j.Job) AS Job_Sequence_Number

FROM THURO.dbo.Job j with (NoLock)
WHERE j.Part_Number = @PartNumber
ORDER BY j.Job  -- Lower job numbers are older

-- ========================================================================
-- PART 2: FirstRun Logic - What SHOULD the current active job be marked as?
-- ========================================================================
SELECT 
    'FIRST RUN ANALYSIS' AS Section,
    j.Job AS Current_Job,
    j.Part_Number,
    j.Status AS Job_Status,
    j.Customer,
    
    -- The FirstRun logic from the view
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist with (NoLock)
            INNER JOIN THURO.dbo.Job_Operation jo_hist with (NoLock) ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist with (NoLock) ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job  -- Previous job (lower job number)
                AND jot_hist.Act_Run_Qty > 0  -- Must have actual production
        ) THEN 'O'  -- Old/Repeat
        ELSE 'F'  -- First Run
    END AS RunIndicator,
    
    -- Explain WHY
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_hist with (NoLock)
            INNER JOIN THURO.dbo.Job_Operation jo_hist with (NoLock) ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist with (NoLock) ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_hist.Part_Number = j.Part_Number
                AND j_hist.Job < j.Job
                AND jot_hist.Act_Run_Qty > 0
        ) THEN 'Marked as OLD/REPEAT because previous jobs have production'
        ELSE 'Marked as FIRST RUN because no previous jobs with production found'
    END AS Explanation,
    
    -- Count previous jobs
    (SELECT COUNT(DISTINCT j_prev.Job)
     FROM THURO.dbo.Job j_prev with (NoLock)
     WHERE j_prev.Part_Number = @PartNumber
       AND j_prev.Job < j.Job
    ) AS Count_Previous_Jobs,
    
    -- Count previous jobs WITH production
    (SELECT COUNT(DISTINCT j_prev.Job)
     FROM THURO.dbo.Job j_prev with (NoLock)
     INNER JOIN THURO.dbo.Job_Operation jo_prev with (NoLock) ON j_prev.Job = jo_prev.Job
     INNER JOIN THURO.dbo.Job_Operation_Time jot_prev with (NoLock) ON jo_prev.Job_Operation = jot_prev.Job_Operation
     WHERE j_prev.Part_Number = @PartNumber
       AND j_prev.Job < j.Job
       AND jot_prev.Act_Run_Qty > 0
    ) AS Count_Previous_Jobs_With_Production,
    
    -- Show which previous jobs had production
    (SELECT STRING_AGG(CAST(j_prev.Job AS VARCHAR), ', ')
     FROM (
         SELECT DISTINCT j_prev.Job
         FROM THURO.dbo.Job j_prev with (NoLock)
         INNER JOIN THURO.dbo.Job_Operation jo_prev with (NoLock) ON j_prev.Job = jo_prev.Job
         INNER JOIN THURO.dbo.Job_Operation_Time jot_prev with (NoLock) ON jo_prev.Job_Operation = jot_prev.Job_Operation
         WHERE j_prev.Part_Number = @PartNumber
           AND j_prev.Job < j.Job
           AND jot_prev.Act_Run_Qty > 0
     ) j_prev
    ) AS Previous_Jobs_With_Production

FROM THURO.dbo.Job j with (NoLock)
WHERE j.Part_Number = @PartNumber
    AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')  -- Only active jobs
ORDER BY j.Job

-- ========================================================================
-- PART 3: Detailed breakdown of previous job production
-- ========================================================================
SELECT 
    'PREVIOUS JOB DETAILS' AS Section,
    j_prev.Job AS Previous_Job,
    j_prev.Status AS Job_Status,
    jo_prev.Work_Center,
    jo_prev.Operation_Service,
    jo_prev.Description,
    SUM(jot_prev.Act_Run_Qty) AS Parts_Produced,
    MAX(jot_prev.Work_Date) AS Last_Production_Date,
    
    -- Was this job complete?
    CASE 
        WHEN j_prev.Status IN ('Complete', 'Closed', 'Shipped') THEN '✓ Complete'
        ELSE '○ Incomplete/Canceled'
    END AS Job_Completion_Status

FROM THURO.dbo.Job j_prev with (NoLock)
    INNER JOIN THURO.dbo.Job_Operation jo_prev with (NoLock) ON j_prev.Job = jo_prev.Job
    LEFT JOIN THURO.dbo.Job_Operation_Time jot_prev with (NoLock) ON jo_prev.Job_Operation = jot_prev.Job_Operation
WHERE j_prev.Part_Number = @PartNumber
    AND EXISTS (
        SELECT 1 FROM THURO.dbo.Job j_curr with (NoLock)
        WHERE j_curr.Part_Number = @PartNumber
          AND j_curr.Status NOT IN ('Complete', 'Closed', 'Shipped')
          AND j_prev.Job < j_curr.Job
    )
GROUP BY j_prev.Job, j_prev.Status, jo_prev.Work_Center, jo_prev.Operation_Service, jo_prev.Description
HAVING SUM(jot_prev.Act_Run_Qty) > 0  -- Only show operations with production
ORDER BY j_prev.Job, jo_prev.Operation_Service

-- ========================================================================
-- PART 4: Summary - Will this show up in First Run tab?
-- ========================================================================
SELECT 
    'FIRST RUN TAB CHECK' AS Section,
    @PartNumber AS Part_Number_Checked,
    
    (SELECT TOP 1 j.Job 
     FROM THURO.dbo.Job j with (NoLock)
     WHERE j.Part_Number = @PartNumber
       AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')
     ORDER BY j.Job DESC
    ) AS Current_Active_Job,
    
    CASE 
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j with (NoLock)
            WHERE j.Part_Number = @PartNumber
              AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')
        ) THEN '✓ Has Active Job'
        ELSE '✗ No Active Jobs'
    END AS Has_Active_Job,
    
    CASE 
        WHEN NOT EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j with (NoLock)
            WHERE j.Part_Number = @PartNumber
              AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')
        ) THEN '✗ No active jobs found'
        
        WHEN NOT EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_curr with (NoLock)
            WHERE j_curr.Part_Number = @PartNumber
              AND j_curr.Status NOT IN ('Complete', 'Closed', 'Shipped')
              AND NOT EXISTS (
                  SELECT 1 
                  FROM THURO.dbo.Job j_hist with (NoLock)
                  INNER JOIN THURO.dbo.Job_Operation jo_hist with (NoLock) ON j_hist.Job = jo_hist.Job
                  INNER JOIN THURO.dbo.Job_Operation_Time jot_hist with (NoLock) ON jo_hist.Job_Operation = jot_hist.Job_Operation
                  WHERE j_hist.Part_Number = j_curr.Part_Number
                    AND j_hist.Job < j_curr.Job
                    AND jot_hist.Act_Run_Qty > 0
              )
        ) THEN '✓ YES - Will show in First Run tab (marked as F)'
        
        ELSE '✗ NO - Will NOT show in First Run tab (marked as O - has previous production)'
    END AS Will_Show_In_FirstRun_Tab,
    
    -- Show the reason
    CASE 
        WHEN NOT EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j with (NoLock)
            WHERE j.Part_Number = @PartNumber
              AND j.Status NOT IN ('Complete', 'Closed', 'Shipped')
        ) THEN 'No active jobs for this part number'
        
        WHEN EXISTS (
            SELECT 1 
            FROM THURO.dbo.Job j_curr with (NoLock)
            INNER JOIN THURO.dbo.Job j_hist with (NoLock) ON j_hist.Part_Number = j_curr.Part_Number AND j_hist.Job < j_curr.Job
            INNER JOIN THURO.dbo.Job_Operation jo_hist with (NoLock) ON j_hist.Job = jo_hist.Job
            INNER JOIN THURO.dbo.Job_Operation_Time jot_hist with (NoLock) ON jo_hist.Job_Operation = jot_hist.Job_Operation
            WHERE j_curr.Part_Number = @PartNumber
              AND j_curr.Status NOT IN ('Complete', 'Closed', 'Shipped')
              AND jot_hist.Act_Run_Qty > 0
        ) THEN CONCAT('Previous job(s) with production exist: ',
            (SELECT STRING_AGG(CAST(j_prev.Job AS VARCHAR), ', ')
             FROM (
                 SELECT DISTINCT j_prev.Job
                 FROM THURO.dbo.Job j_curr with (NoLock)
                 INNER JOIN THURO.dbo.Job j_prev with (NoLock) ON j_prev.Part_Number = j_curr.Part_Number AND j_prev.Job < j_curr.Job
                 INNER JOIN THURO.dbo.Job_Operation jo_prev with (NoLock) ON j_prev.Job = jo_prev.Job
                 INNER JOIN THURO.dbo.Job_Operation_Time jot_prev with (NoLock) ON jo_prev.Job_Operation = jot_prev.Job_Operation
                 WHERE j_curr.Part_Number = @PartNumber
                   AND j_curr.Status NOT IN ('Complete', 'Closed', 'Shipped')
                   AND jot_prev.Act_Run_Qty > 0
             ) j_prev
            ))
        
        ELSE 'No previous jobs with production - qualifies as First Run'
    END AS Reason

-- ========================================================================
-- INSTRUCTIONS:
-- 1. Change @PartNumber at the top to your part number (default: '858046-1')
-- 2. Run all 4 parts
-- 3. Part 1: Shows complete job history for this part
-- 4. Part 2: Shows why current job is marked F or O
-- 5. Part 3: Shows details of previous production
-- 6. Part 4: Summary - will it show in First Run tab?
-- ========================================================================
