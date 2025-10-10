-- ========================================================================
-- MODIFICATION: Add Deburring Exception to vw_MachineStatus_GG
-- Deburring is NOT a machine - show ALL deburring jobs (no deduplication)
-- ========================================================================

USE [THURO]
GO

-- ========================================================================
-- FIND THIS SECTION AT THE VERY END OF YOUR VIEW (after the UNION ALL)
-- This is the final SELECT that filters to machine_rank = 1
-- ========================================================================

/*
CURRENT CODE (at the very end of the view):
----------------------------------------
WHERE 
    -- Use machine_rank to keep only one record per machine
    machine_rank = 1
     
ORDER BY Department, Machine
*/

-- ========================================================================
-- REPLACE WITH THIS:
-- ========================================================================

WHERE 
    -- Use machine_rank to keep only one record per machine
    machine_rank = 1
    
    -- EXCEPTION: Deburring is NOT a machine - show ALL deburring jobs
    OR Department = 'Deburring'
     
ORDER BY Department, Machine

-- ========================================================================
-- EXPLANATION:
-- ========================================================================
/*
The original WHERE clause filters to only show the #1 ranked job per machine.

By adding "OR Department = 'Deburring'", we bypass the deduplication for
ALL jobs in the Deburring department.

This means:
- Swiss, Turning, Milling, Multis, Grinding, Washing: ONE job per machine (as before)
- Deburring: ALL jobs shown (no deduplication)

This works because:
1. Machine-based departments still filter to machine_rank = 1
2. Deburring jobs ALL show regardless of their machine_rank value
3. Both conditions are OR'd together
*/

-- ========================================================================
-- FULL CONTEXT - WHERE TO MAKE THE CHANGE:
-- ========================================================================
/*
Your view structure looks like this:

WITH 
    FirstRunIdentifier AS (...),
    JobCompletionPredictions AS (...),
    MachineStatusCTE AS (
        SELECT ... 
        ROW_NUMBER() OVER (PARTITION BY w.Work_Center ORDER BY ...) AS machine_rank
        FROM ...
        
        UNION ALL
        
        SELECT ...
        FROM ... (missing machines section)
    )

-- NULL-SAFE OUTPUTS
SELECT 
    ...columns...
FROM (
    SELECT *,
        ... some additional calculations ...
    FROM MachineStatusCTE
) filtered
WHERE 
    machine_rank = 1  ← CHANGE THIS LINE TO ADD THE OR CONDITION
     
ORDER BY Department, Machine
GO
*/

-- ========================================================================
-- STEP-BY-STEP MODIFICATION GUIDE:
-- ========================================================================
/*
1. Open your view: vw_MachineStatus_GG_WITH_FIRSTRUN.sql
2. Scroll to the VERY END (last ~10 lines)
3. Find this line:
   WHERE machine_rank = 1
   
4. Change it to:
   WHERE 
       machine_rank = 1
       OR Department = 'Deburring'
   
5. Save and execute to update the view
6. Test by querying jobs in Deburring - you should now see BOTH 1317286 AND 1317620
*/

-- ========================================================================
-- AFTER THE CHANGE, RUN THIS TO TEST:
-- ========================================================================
SELECT 
    Machine,
    Department,
    CustomerPartJob,
    MachineStatus,
    ProgressDisplay
FROM THURO.dbo.vw_MachineStatus_GG
WHERE Department LIKE '%Deburr%'
ORDER BY Machine, CustomerPartJob

-- You should now see MULTIPLE jobs per Deburring work center!

-- ========================================================================
-- ALTERNATIVE: If you have MULTIPLE non-machine departments
-- ========================================================================
/*
If you have OTHER departments like Deburring that are also bench work areas,
you can list them all:

WHERE 
    machine_rank = 1
    OR Department IN ('Deburring', 'Washing', 'Assembly')  -- List all non-machine depts
*/
