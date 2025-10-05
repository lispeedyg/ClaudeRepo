-- ========================================================================
-- FIRSTRUN INDICATOR IMPLEMENTATION
-- Changes needed for vw_MachineStatus_GG.sql
-- ========================================================================

-- CHANGE 1: Add new CTE at the beginning (after "WITH" statement)
-- Replace line:  WITH JobCompletionPredictions AS (
-- With:

WITH 
-- NEW: FirstRun Identifier - Check if part number has been run before
FirstRunIdentifier AS (
    SELECT DISTINCT
        j.Job,
        j.Part_Number,
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
        END AS RunIndicator
    FROM THURO.dbo.Job j with (NoLock)
    WHERE j.Status NOT IN ('Complete', 'Closed', 'Shipped')
),

JobCompletionPredictions AS (
    -- ... rest of CTE continues unchanged ...


-- CHANGE 2: Add JOIN in PART 1 (after ship_dates join, before WHERE clause)
-- Add this JOIN before the WHERE clause in PART 1:

            -- NEW: Join FirstRun indicator
            LEFT JOIN FirstRunIdentifier first_run ON first_run.Job = j.Job


-- CHANGE 3: Modify MachineStatus field in PART 1
-- Find the section that says "-- Individual Status Fields - ENHANCED to handle setup statuses"
-- Replace the entire "AS MachineStatus," block with:

            -- Individual Status Fields - ENHANCED to handle setup statuses + FirstRun Indicator
            CONCAT(
                CASE 
                    WHEN current_op.Status = 'C' THEN 
                        CASE 
                            WHEN setup_for_machine.setup_status = 'ACTIVE SUP' THEN 'STAGING'
                            WHEN setup_for_machine.setup_status IN ('SUP IDLE', 'SUP STALLED') THEN 'STAGING-IDLE'
                            WHEN setup_for_machine.setup_status = 'SUP COMPLETE' THEN 'STAGED'
                            ELSE 'OFFLINE'
                        END
                    WHEN current_op.Job_Operation IS NULL THEN 
                        CASE 
                            WHEN setup_for_machine.setup_status = 'ACTIVE SETUP' THEN 'STAGING'
                            WHEN setup_for_machine.setup_status IN ('SETUP IDLE', 'SETUP STALLED') THEN 'STAGING-IDLE'
                            WHEN setup_for_machine.setup_status = 'SETUP COMPLETE' THEN 'STAGED'
                            ELSE 'OFFLINE'
                        END
                    -- ORIGINAL STATUS LOGIC UNCHANGED
                    WHEN latest_activity.Operation_Complete = 1 OR current_op.Status IN ('Complete', 'Closed')
                    THEN 'OFFLINE'
                    -- Check if quantity is 100%+ complete but still producing (over plan)
                    WHEN current_op.Est_Required_Qty > 0 AND op_totals.Total_Run_Qty >= current_op.Est_Required_Qty
                    THEN 'OverPlan'
                    -- Handle cases with no recent activity  
                    WHEN latest_activity.Last_Updated IS NULL THEN 'OFFLINE'
                    -- Active cases
                    WHEN latest_activity.Operation_Complete = 0 AND current_op.Status NOT IN ('Complete', 'Closed') 
                         AND latest_activity.Last_Updated IS NOT NULL
                         AND latest_activity.Last_Updated >= DATEADD(DAY, (-30), GETDATE())
                         AND DATEDIFF(HOUR, latest_activity.Last_Updated, GETDATE()) <= 8
                    THEN 'ACTIVE'
                    WHEN latest_activity.Operation_Complete = 0 AND current_op.Status NOT IN ('Complete', 'Closed')
                         AND latest_activity.Last_Updated IS NOT NULL
                    THEN 'IDLE'
                    ELSE 'UNKNOWN'
                END,
                ' | ',
                ISNULL(first_run.RunIndicator, 'O')  -- Add FirstRun indicator (F or O)
            ) AS MachineStatus,


-- ========================================================================
-- SUMMARY OF CHANGES:
-- ========================================================================
-- 1. Added FirstRunIdentifier CTE that checks if a part number has been 
--    run before in any previous job with actual production
-- 2. Added LEFT JOIN to FirstRunIdentifier in PART 1
-- 3. Modified MachineStatus field to CONCAT the status with " | F" or " | O"
--    - F = FirstRun (part never run before)
--    - O = Old/Repeat (part has been run before)
-- 4. PART 2 (missing machines) is left unchanged since they don't have 
--    active jobs to check
-- ========================================================================

-- EXAMPLE OUTPUTS:
-- MachineStatus before:  'ACTIVE'
-- MachineStatus after:   'ACTIVE | F'  (if first run)
--                        'ACTIVE | O'  (if repeat)
-- ========================================================================
