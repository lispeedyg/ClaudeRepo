# JobAI Quick Start Guide

## Prerequisites

Before you begin, ensure you have:
- Node.js 18+ installed (https://nodejs.org/)
- SQL Server access to THURO database
- Anthropic API key (for Claude AI integration)
- Git (optional, for version control)

## Setup Instructions

### Step 1: Set Up Backend API

1. **Navigate to Backend Directory**
   ```bash
   cd C:\ClaudeRepo\Clients\TMP\JobAI\Backend
   ```

2. **Install Dependencies**
   ```bash
   npm install
   ```

3. **Configure Environment**
   - Copy `.env.example` to `.env`
   ```bash
   copy .env.example .env
   ```
   
   - Edit `.env` and update:
     ```
     DB_SERVER=YOUR_SQL_SERVER_NAME
     DB_DATABASE=THURO
     ANTHROPIC_API_KEY=your_anthropic_api_key_here
     ```

4. **Start the Backend Server**
   ```bash
   npm start
   ```
   
   You should see:
   ```
   ╔════════════════════════════════════════╗
   ║         JobAI API Server               ║
   ║  Status: Running                       ║
   ║  Port: 5000                            ║
   ╚════════════════════════════════════════╝
   ```

5. **Test the API**
   - Open browser to: `http://localhost:5000/api/health`
   - Should see: `{"status":"OK",...}`

### Step 2: Set Up Frontend Application

1. **Open New Terminal/Command Prompt**
   
2. **Navigate to Frontend Directory**
   ```bash
   cd C:\ClaudeRepo\Clients\TMP\JobAI\Frontend
   ```

3. **Install Dependencies**
   ```bash
   npm install
   ```

4. **Start the Development Server**
   ```bash
   npm start
   ```
   
   The application will automatically open in your browser at:
   `http://localhost:3000`

### Step 3: Test the Application

1. **Enter a Test Job Number**
   - Try: `1317608` or `1317620`
   - Click "Search Job"

2. **View Job Traveler**
   - You should see a complete table with ALL operations
   - Click on rows to expand details
   - Review status badges and action items

3. **Request AI Analysis**
   - Click "Request AI Analysis" button
   - Wait for Claude to analyze the job
   - Review recommendations and insights

## Folder Structure

```
JobAI/
├── SQL/                          # Database queries
│   └── Job_Traveler_All_Operations.sql
│
├── Backend/                      # Node.js API Server
│   ├── server.js                # Main server file
│   ├── package.json             # Dependencies
│   ├── .env.example             # Environment template
│   └── .env                     # Your config (create this)
│
├── Frontend/                     # React Application
│   ├── public/
│   │   └── index.html
│   ├── src/
│   │   ├── components/
│   │   │   ├── JobTraveler.js   # Main table component
│   │   │   ├── JobTraveler.css
│   │   │   ├── JobAnalysis.js   # AI analysis component
│   │   │   └── JobAnalysis.css
│   │   ├── App.js               # Main app component
│   │   ├── App.css
│   │   ├── index.js
│   │   └── index.css
│   └── package.json
│
├── README.md                     # Full documentation
└── QUICKSTART.md                # This file
```

## Common Issues & Solutions

### Issue: Backend won't connect to SQL Server

**Solution:**
- Verify SQL Server name in `.env` file
- Ensure Windows Authentication is configured
- Check that you have access to THURO database
- Try: `sqlcmd -S YOUR_SERVER_NAME -d THURO -Q "SELECT TOP 1 * FROM Job"`

### Issue: "Job not found" error

**Solution:**
- Verify job number exists in THURO database
- Try known job numbers: 1317608, 1317620, 1317512
- Check SQL query directly in SSMS first

### Issue: AI Analysis returns error

**Solution:**
- Verify ANTHROPIC_API_KEY is set in `.env`
- Test API key at: https://console.anthropic.com
- Check backend server logs for detailed error

### Issue: CORS errors in browser console

**Solution:**
- Ensure backend is running on port 5000
- Check CORS_ORIGIN in backend `.env` matches frontend URL
- Restart both servers after changing configuration

### Issue: Frontend won't start

**Solution:**
- Delete `node_modules` folder
- Delete `package-lock.json`
- Run `npm install` again
- Make sure port 3000 is not already in use

## Development Workflow

### Making Changes to Backend:
1. Edit `Backend/server.js` or add new files
2. Backend will auto-restart (if using `npm run dev` with nodemon)
3. Test changes at `http://localhost:5000`

### Making Changes to Frontend:
1. Edit files in `Frontend/src/`
2. Changes automatically reload in browser
3. Check browser console for errors

### Testing SQL Queries:
1. Edit queries in `SQL/` folder
2. Test in SQL Server Management Studio first
3. Update backend `server.js` with new queries
4. Restart backend server

## Next Steps

1. **Customize Styling**
   - Edit CSS files in `Frontend/src/components/`
   - Modify colors in `App.css` for branding

2. **Add More Features**
   - Create new components in `Frontend/src/components/`
   - Add new API endpoints in `Backend/server.js`
   - Write additional SQL queries in `SQL/` folder

3. **Deploy to Production**
   - See README.md for deployment instructions
   - Consider hosting on Azure, AWS, or internal server

4. **Enhance AI Prompts**
   - Modify Claude prompts in `Backend/server.js`
   - Add more context for better analysis

## Support

For issues or questions:
- Review full documentation: `README.md`
- Check SQL queries: `SQL/` folder
- Review code comments in source files

## Important Files to Know

**Backend:**
- `server.js` - Main API logic, routes, Claude integration
- `.env` - Configuration (create from `.env.example`)

**Frontend:**
- `App.js` - Main application logic
- `JobTraveler.js` - Job traveler table component
- `JobAnalysis.js` - AI analysis component

**SQL:**
- `Job_Traveler_All_Operations.sql` - Core query for job data

---

**You're Ready!** The JobAI application is now set up and running.

Enter a job number and start exploring intelligent job analysis!
