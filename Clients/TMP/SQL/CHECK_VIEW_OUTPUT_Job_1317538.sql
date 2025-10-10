-- ========================================================================
-- CHECK WHAT THE VIEW IS ACTUALLY RETURNING
-- Purpose: See if Job 1317538 appears in the view at all
-- ========================================================================

USE [THURO]
GO

-- Query the ACTUAL view to see if Job 1317538 is there
SELECT 
    'VIEW OUTPUT CHECK' AS Section,
    *
FROM [dbo].[vw_MachineStatus_GG]
WHERE CustomerPartJob LIKE '%1317538%'
   OR CustomerPartJob LIKE '%8580464-1%'

-- If nothing returned, check if it's in the base data at all
IF NOT EXISTS (SELECT 1 FROM [dbo].[vw_MachineStatus_GG] WHERE CustomerPartJob LIKE '%1317538%')
BEGIN
    SELECT 
        'JOB NOT IN VIEW - CHECKING WHY' AS Section,
        j.Job,
        j.Part_Number,
        j.Status AS Job_Status,
        j.Customer,
        w.Work_Center AS Machine,
        w.Department,
        w.Status AS Machine_Status,
        w.UVText1 AS Machine_Flag,
        
        -- Check the view's WHERE clause conditions
        CASE 
            WHEN w.Status != 1 THEN '✗ EXCLUDED: Machine Status != 1'
            WHEN w.UVText1 != 'MStatusQry' THEN '✗ EXCLUDED: Machine UVText1 != MStatusQry'
            WHEN w.Department NOT IN ('Swiss','Turning','Multis','Milling','Grinding','Deburring','Washing') 
                THEN '✗ EXCLUDED: Department not in list'
            WHEN j.Status IN ('Complete', 'Closed', 'Shipped') THEN '✗ EXCLUDED: Job is Complete/Closed/Shipped'
            WHEN NOT EXISTS (
                SELECT 1 FROM THURO.dbo.Job_Operation jo
                INNER JOIN THURO.dbo.Job_Operation_Time jot ON jo.Job_Operation = jot.Job_Operation
                WHERE jo.Job = j.Job 
                  AND jot.Work_Date >= DATEADD(DAY, -7, GETDATE())
                  AND jot.Work_Date IS NOT NULL
                  AND jot.Last_Updated IS NOT NULL
            ) THEN '✗ EXCLUDED: No activity in last 7 days'
            ELSE '✓ Should be included'
        END AS Exclusion_Reason
        
    FROM THURO.dbo.Job j with (NoLock)
        LEFT JOIN THURO.dbo.Job_Operation jo with (NoLock) ON j.Job = jo.Job
        LEFT JOIN THURO.dbo.Work_Center w with (NoLock) ON jo.Work_Center = w.Work_Center
    WHERE j.Job = '1317538'
END

-- Check if ENGRELEASE machine exists in the view at all
SELECT 
    'ENGRELEASE MACHINE CHECK' AS Section,
    Machine,
    Department,
    CustomerPartJob,
    MachineStatus,
    LastUpdated
FROM [dbo].[vw_MachineStatus_GG]
WHERE Machine = 'ENGRELEASE'

-- Show all First Run jobs currently in the view
SELECT 
    'ALL FIRST RUN JOBS IN VIEW' AS Section,
    Machine,
    Department,
    CustomerPartJob,
    JobDueDtStatus,
    OperationDetails,
    MachineStatus,
    LastUpdated
FROM [dbo].[vw_MachineStatus_GG]
WHERE MachineStatus LIKE '%F%'  -- Contains 'F' for First Run
   OR MachineStatus LIKE '%| F'  -- Ends with F indicator
ORDER BY Department, Machine

-- ========================================================================
-- INSTRUCTIONS:
-- This will show you if Job 1317538 appears in the view at all
-- and if not, exactly why it's being excluded
-- ========================================================================
