/**
 * JobAI Backend API Server
 * 
 * Main Express server that provides:
 * 1. Job Traveler data endpoints
 * 2. Claude AI integration for job analysis
 * 3. RESTful API for frontend consumption
 */

const express = require('express');
const cors = require('cors');
const sql = require('mssql');
require('dotenv').config();

const app = express();
const PORT = process.env.PORT || 5000;

// Middleware
app.use(cors());
app.use(express.json());

// Database configuration
const dbConfig = {
  server: process.env.DB_SERVER || 'YOUR_SQL_SERVER',
  database: process.env.DB_DATABASE || 'THURO',
  options: {
    trustedConnection: true,
    encrypt: true,
    trustServerCertificate: true,
    enableArithAbort: true
  }
};

// Database connection pool
let pool;

/**
 * Initialize database connection pool
 */
async function initializeDatabase() {
  try {
    pool = await sql.connect(dbConfig);
    console.log('✓ Connected to SQL Server database');
    return pool;
  } catch (error) {
    console.error('✗ Database connection failed:', error);
    throw error;
  }
}

/**
 * GET /api/health
 * Health check endpoint
 */
app.get('/api/health', (req, res) => {
  res.json({
    status: 'OK',
    timestamp: new Date().toISOString(),
    service: 'JobAI API',
    database: pool ? 'Connected' : 'Disconnected'
  });
});

/**
 * GET /api/job-traveler/:jobNumber
 * 
 * Returns complete job traveler data for a specific job
 * This is the "opening set of facts" - all operations, all details
 * 
 * Response Format:
 * {
 *   job: { jobNumber, customer, partNumber, status, statusDate },
 *   operations: [ { sequence, workCenter, description, status, ... } ],
 *   summary: { setupOperations, productionOperations, ... }
 * }
 */
app.get('/api/job-traveler/:jobNumber', async (req, res) => {
  const { jobNumber } = req.params;

  try {
    // Execute the job traveler query
    const result = await pool.request()
      .input('JobNumber', sql.VarChar(50), jobNumber)
      .query(`
        -- Job Traveler Query - All Operations
        SELECT 
            j.Job,
            j.Customer,
            j.Part_Number,
            j.Status AS Job_Status,
            j.Status_Date AS Job_Status_Date,
            
            jo.Job_Operation,
            jo.Sequence,
            jo.Work_Center,
            jo.Operation_Service,
            jo.Description,
            jo.Status AS Op_Status_Code,
            
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
            
            time_summary.Total_Hours,
            time_summary.Total_Qty_Produced,
            time_summary.Last_Work_Date,
            time_summary.Days_Since_Last_Work,
            time_summary.Latest_Operator,
            
            CASE 
                WHEN jo.Work_Center = 'SM SETUPM' AND jo.Status IN ('C', 'Complete', 'Closed')
                THEN 'Setup Complete'
                WHEN jo.Work_Center = 'SM SETUPM' AND jo.Status NOT IN ('C', 'Complete', 'Closed')
                THEN 'Setup OPEN - Needs Closure'
                WHEN jo.Work_Center != 'SM SETUPM' AND jo.Status IN ('C', 'Complete', 'Closed')
                THEN 'Production Complete'
                WHEN jo.Work_Center != 'SM SETUPM' AND jo.Status = 'S'
                THEN 'Production Started'
                WHEN jo.Work_Center != 'SM SETUPM' AND jo.Status = 'O'
                THEN 'Production Open'
                ELSE 'Other Status'
            END AS Status_Check,
            
            CASE 
                WHEN jo.Work_Center = 'SM SETUPM' 
                     AND jo.Status NOT IN ('C', 'Complete', 'Closed')
                     AND EXISTS (
                         SELECT 1 FROM THURO.dbo.Job_Operation jo_prod
                         WHERE jo_prod.Job = jo.Job
                           AND jo_prod.Work_Center != 'SM SETUPM'
                           AND jo_prod.Status IN ('C', 'Complete', 'Closed')
                     )
                THEN 'CLEANUP NEEDED: Close this setup operation'
                WHEN jo.Work_Center = 'SM SETUPM' 
                     AND jo.Status NOT IN ('C', 'Complete', 'Closed')
                THEN 'Setup still open (may be OK if production is active)'
                WHEN jo.Status IN ('C', 'Complete', 'Closed')
                THEN 'No action needed'
                ELSE 'Active operation'
            END AS Action_Needed

        FROM THURO.dbo.Job j
            INNER JOIN THURO.dbo.Job_Operation jo ON j.Job = jo.Job
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
      `);

    if (result.recordset.length === 0) {
      return res.status(404).json({
        error: 'Job not found',
        jobNumber: jobNumber
      });
    }

    // Transform data into structured format
    const firstRow = result.recordset[0];
    const jobData = {
      job: {
        jobNumber: firstRow.Job,
        customer: firstRow.Customer,
        partNumber: firstRow.Part_Number,
        status: firstRow.Job_Status,
        statusDate: firstRow.Job_Status_Date
      },
      operations: result.recordset.map(row => ({
        jobOperation: row.Job_Operation,
        sequence: row.Sequence,
        workCenter: row.Work_Center,
        operationService: row.Operation_Service,
        description: row.Description,
        statusCode: row.Op_Status_Code,
        statusMeaning: row.Op_Status_Meaning,
        actualStart: row.Actual_Start,
        requiredQty: row.Est_Required_Qty,
        totalHours: row.Total_Hours || 0,
        qtyProduced: row.Total_Qty_Produced || 0,
        lastWorkDate: row.Last_Work_Date,
        daysSinceLastWork: row.Days_Since_Last_Work,
        latestOperator: row.Latest_Operator,
        statusCheck: row.Status_Check,
        actionNeeded: row.Action_Needed
      })),
      summary: {
        totalOperations: result.recordset.length,
        setupOperations: result.recordset.filter(r => r.Work_Center === 'SM SETUPM').length,
        productionOperations: result.recordset.filter(r => r.Work_Center !== 'SM SETUPM').length,
        completeOperations: result.recordset.filter(r => r.Op_Status_Code === 'C').length,
        activeOperations: result.recordset.filter(r => r.Op_Status_Code === 'S').length,
        openOperations: result.recordset.filter(r => r.Op_Status_Code === 'O').length
      }
    };

    res.json(jobData);

  } catch (error) {
    console.error('Error fetching job traveler:', error);
    res.status(500).json({
      error: 'Failed to fetch job traveler data',
      message: error.message
    });
  }
});

/**
 * POST /api/job-analysis/:jobNumber
 * 
 * Performs AI analysis on a job using Claude
 * Requires: Anthropic API key in environment
 */
app.post('/api/job-analysis/:jobNumber', async (req, res) => {
  const { jobNumber } = req.params;

  try {
    // First, get the job traveler data
    const travelerResponse = await fetch(`http://localhost:${PORT}/api/job-traveler/${jobNumber}`);
    const travelerData = await travelerResponse.json();

    if (!travelerResponse.ok) {
      return res.status(404).json({
        error: 'Job not found',
        jobNumber: jobNumber
      });
    }

    // Call Claude API for analysis
    const anthropicResponse = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 2000,
        messages: [{
          role: 'user',
          content: `Analyze this manufacturing job and provide insights:

JOB HEADER:
- Job: ${travelerData.job.jobNumber}
- Customer: ${travelerData.job.customer}
- Part Number: ${travelerData.job.partNumber}
- Status: ${travelerData.job.status}

OPERATIONS:
${travelerData.operations.map(op => `
  Sequence ${op.sequence}: ${op.description}
  - Work Center: ${op.workCenter}
  - Status: ${op.statusMeaning}
  - Hours Worked: ${op.totalHours}
  - Qty Produced: ${op.qtyProduced} / ${op.requiredQty}
  - Last Activity: ${op.daysSinceLastWork ? op.daysSinceLastWork + ' days ago' : 'Never started'}
  - Latest Operator: ${op.latestOperator || 'N/A'}
  - Action Needed: ${op.actionNeeded}
`).join('\n')}

SUMMARY:
- Total Operations: ${travelerData.summary.totalOperations}
- Complete: ${travelerData.summary.completeOperations}
- Active: ${travelerData.summary.activeOperations}
- Open: ${travelerData.summary.openOperations}

Please provide:
1. Job Health Assessment (1-2 sentences)
2. Bottleneck Identification (if any)
3. Top 3 Recommendations
4. Cleanup Actions Needed
5. Estimated Completion Timeline

Format your response in clear sections with headers.`
        }]
      })
    });

    const analysisResult = await anthropicResponse.json();

    res.json({
      jobNumber: jobNumber,
      analysis: analysisResult.content[0].text,
      travelerData: travelerData,
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error('Error performing job analysis:', error);
    res.status(500).json({
      error: 'Failed to analyze job',
      message: error.message
    });
  }
});

/**
 * Start the server
 */
async function startServer() {
  try {
    // Initialize database connection
    await initializeDatabase();

    // Start Express server
    app.listen(PORT, () => {
      console.log(`
╔════════════════════════════════════════╗
║         JobAI API Server               ║
║                                        ║
║  Status: Running                       ║
║  Port: ${PORT}                           ║
║  Database: Connected                   ║
║                                        ║
║  Endpoints:                            ║
║  - GET  /api/health                    ║
║  - GET  /api/job-traveler/:jobNumber   ║
║  - POST /api/job-analysis/:jobNumber   ║
╚════════════════════════════════════════╝
      `);
    });
  } catch (error) {
    console.error('Failed to start server:', error);
    process.exit(1);
  }
}

// Handle graceful shutdown
process.on('SIGINT', async () => {
  console.log('\n\nShutting down gracefully...');
  if (pool) {
    await pool.close();
  }
  process.exit(0);
});

// Start the server
startServer();
