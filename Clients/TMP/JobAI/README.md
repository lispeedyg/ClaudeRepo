# JobAI - Intelligent Job Analysis Dashboard

## Project Overview

JobAI is an AI-powered manufacturing job analysis system that provides comprehensive insights into job routing, operations, timing, and status. The system integrates SQL Server data with Claude AI to deliver intelligent analysis and recommendations for job management.

## Project Structure

```
JobAI/
├── SQL/                    # Database queries and stored procedures
│   └── Job_Traveler_All_Operations.sql   # Core query - Job traveler data
├── Backend/                # Node.js/Express API
│   ├── server.js          # Main API server
│   ├── routes/            # API route handlers
│   └── controllers/       # Business logic
├── Frontend/              # React application
│   ├── src/
│   │   ├── components/   # React components
│   │   ├── services/     # API service layer
│   │   └── utils/        # Utility functions
│   └── public/           # Static assets
└── README.md             # This file
```

## Key Concept: Opening Set of Facts

The foundation of JobAI is the **Job Traveler Query** which provides complete context about a job:

### What the Query Returns:
1. **Job Header Information**
   - Job number, customer, part number
   - Overall job status and status date

2. **Complete Operation Details**
   - ALL operations (not filtered by cleanup status)
   - Sequence, work center, operation service
   - Status codes and human-readable meanings
   - Actual start dates and required quantities

3. **Time Entry Summaries**
   - Total hours worked per operation
   - Quantities produced
   - Last work date and days since activity
   - Latest operator who worked on each operation

4. **Intelligent Status Checks**
   - Setup completion status
   - Production status indicators
   - Cleanup warnings
   - Action items needed

### Why This Matters:

This "opening set of facts" displayed in **tabular form** provides the complete context that:
- Users can quickly scan and understand the job state
- AI (Claude) can reference for intelligent analysis
- Dashboard components can build upon
- Eliminates the need to make assumptions about job status

## Architecture Design

### 1. Data Layer (SQL)
- **Primary Query**: `Job_Traveler_All_Operations.sql`
- **Purpose**: Retrieve complete, unfiltered job and operation data
- **Output**: Structured dataset ready for API consumption

### 2. Backend API
- **Technology**: Node.js + Express (or ASP.NET Core)
- **Key Endpoints**:
  - `GET /api/job-traveler/:jobNumber` - Get complete job data
  - `POST /api/job-analysis/:jobNumber` - AI analysis of job
  - `GET /api/job-recommendations/:jobNumber` - Action recommendations

### 3. Frontend Dashboard
- **Technology**: React
- **Key Features**:
  - **Job Traveler Table** (Top Section)
    - Displays complete operation data
    - Expandable/collapsible rows
    - Color-coded status indicators
    - Responsive design
  
  - **AI Analysis Section** (Main Section)
    - Claude-powered insights
    - Bottleneck identification
    - Efficiency recommendations
    - Timeline visualization
  
  - **Action Items Panel** (Side/Bottom)
    - Prioritized recommendations
    - Cleanup warnings
    - Follow-up actions

## Integration with Claude AI

### Context Passing Strategy:

When requesting AI analysis, the job traveler data is passed to Claude as structured context:

```javascript
const prompt = `
Analyze this job based on the complete traveler data:

JOB HEADER:
- Job: ${jobData.Job}
- Customer: ${jobData.Customer}
- Part Number: ${jobData.Part_Number}
- Status: ${jobData.Job_Status}

OPERATIONS:
${jobData.operations.map(op => `
  Seq ${op.Sequence}: ${op.Description}
  - Work Center: ${op.Work_Center}
  - Status: ${op.Op_Status_Meaning}
  - Hours: ${op.Total_Hours}
  - Last Activity: ${op.Days_Since_Last_Work} days ago
  - Latest Operator: ${op.Latest_Operator}
`).join('\n')}

Based on this data, provide:
1. Current job health assessment
2. Bottleneck identification
3. Efficiency recommendations
4. Cleanup actions needed
`;
```

## Refactoring Goals

### From Previous Implementation:
The original JobAI code had architectural issues:
- 2000+ lines of monolithic HTML/CSS/JS
- Hard-coded data in templates
- Over-engineered tooltip system
- Performance issues with large datasets

### Current Refactoring Approach:
1. **Modular Architecture**
   - Separate concerns (data, UI, logic)
   - Reusable components
   - Testable code

2. **Clean Data Flow**
   - SQL → API → Frontend → Claude
   - Structured JSON at each layer
   - Clear transformation points

3. **Performance First**
   - Lazy loading of operations
   - Efficient rendering
   - Caching strategies

4. **Mobile Ready**
   - Responsive tables
   - Touch-friendly UI
   - Progressive enhancement

## Development Roadmap

### Phase 1: Foundation (Current)
- [x] Create folder structure
- [x] Document job traveler query
- [ ] Create API skeleton
- [ ] Build basic React app
- [ ] Implement job traveler table display

### Phase 2: Core Features
- [ ] Integrate Claude AI analysis
- [ ] Add operation detail views
- [ ] Implement status visualizations
- [ ] Create action item system

### Phase 3: Intelligence
- [ ] Historical job analysis
- [ ] Predictive bottleneck detection
- [ ] Operator efficiency tracking
- [ ] Automated recommendations

### Phase 4: Enterprise Features
- [ ] Multi-job comparison
- [ ] Real-time updates
- [ ] Advanced reporting
- [ ] Mobile app

## Getting Started

### Prerequisites:
- Node.js 18+ (or .NET 8 for ASP.NET backend)
- SQL Server access to THURO database
- React development environment

### Quick Start:

1. **Clone Repository**
   ```bash
   cd C:\ClaudeRepo\Clients\TMP\JobAI
   ```

2. **Set Up Backend**
   ```bash
   cd Backend
   npm install
   # Configure connection string in config
   npm start
   ```

3. **Set Up Frontend**
   ```bash
   cd Frontend
   npm install
   npm start
   ```

4. **Test with Sample Job**
   - Navigate to http://localhost:3000
   - Enter job number: 1317608
   - View job traveler data
   - Request AI analysis

## Configuration

### Database Connection:
Update `Backend/config/database.js`:
```javascript
module.exports = {
  server: 'YOUR_SQL_SERVER',
  database: 'THURO',
  options: {
    trustedConnection: true,
    encrypt: true,
    trustServerCertificate: true
  }
};
```

### Claude AI Integration:
Set environment variable:
```bash
ANTHROPIC_API_KEY=your_api_key_here
```

## Data Model

### Job Traveler Object Structure:
```javascript
{
  job: {
    jobNumber: "1317608",
    customer: "SMP",
    partNumber: "805004-1137-30",
    status: "Active",
    statusDate: "2025-07-29"
  },
  operations: [
    {
      sequence: 0,
      workCenter: "ENGRELEASE",
      description: "ROUTER APPROVED FOR MFG",
      statusCode: "C",
      statusMeaning: "Complete",
      actualStart: null,
      requiredQty: 50000,
      totalHours: 0,
      qtyProduced: 0,
      lastWorkDate: null,
      daysSinceLastWork: null,
      latestOperator: null,
      statusCheck: "✓ Setup Complete",
      actionNeeded: "✓ No action needed"
    },
    // ... more operations
  ],
  summary: {
    setupOperations: 6,
    productionOperations: 6,
    setupStatus: "C",
    productionStatus: "S",
    willShowCleanupWarning: false
  }
}
```

## Best Practices

1. **Always show complete data** - Don't filter operations unless explicitly requested
2. **Tabular display first** - Show raw data before AI interpretation
3. **Context is king** - Pass complete job traveler data to Claude
4. **Performance matters** - Lazy load, cache, optimize
5. **Error handling** - Always gracefully handle missing data
6. **Mobile first** - Design for small screens, enhance for large

## Contributing

When adding new features:
1. Update SQL queries in `/SQL` folder
2. Create/update API endpoints in `/Backend`
3. Build UI components in `/Frontend`
4. Update this README with new capabilities
5. Test with real job numbers from THURO database

## Testing

### Test Job Numbers:
- 1317608 - Complex job with multiple operations
- 1317620 - Job with cleanup warning
- 1317512 - Standard production job

### Test Scenarios:
1. Job with all operations complete
2. Job with open setup and complete production (cleanup needed)
3. Job with active production
4. Job with no time entries yet
5. Job with multiple operators

## License

Internal use for TMP/IQ Associates clients only.

## Support

For questions or issues:
- Contact: Development Team
- Repository: C:\ClaudeRepo\Clients\TMP\JobAI
- Documentation: This README

---

**Last Updated**: October 10, 2025
**Version**: 1.0.0 - Initial Structure
**Status**: Foundation Phase - Building Core Architecture
