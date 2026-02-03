#!/usr/bin/env node

/**
 * SDD Plugin - Environment Setup Hook
 * This hook runs at session start to:
 * 1. Set SDD_ROOT_DIR environment variable
 * 2. Create directory structure if not exists
 * 3. Copy reference templates to data directory
 * 4. Detect active tickets and set CLAUDE_TASK_LIST_ID (Tasks API integration)
 */

const fs = require('fs');
const path = require('path');

const SDD_ROOT = process.env.SDD_ROOT_DIR || '/app/.sdd';

// Directories to create under SDD_ROOT
const directories = [
  'epics',
  'tickets',
  'archive/tickets',
  'archive/epics',
  'reference',
  'research',
  'scratchpad',
  'logs'
];

// Create directory structure if not exists
if (!fs.existsSync(SDD_ROOT)) {
  for (const dir of directories) {
    fs.mkdirSync(path.join(SDD_ROOT, dir), { recursive: true });
  }
}

// Copy reference template if plugin root available and template doesn't exist
const pluginRoot = process.env.CLAUDE_PLUGIN_ROOT;
if (pluginRoot) {
  const templateSrc = path.join(
    pluginRoot,
    'skills/project-workflow/templates/ticket/task-template.md'
  );
  const templateDest = path.join(SDD_ROOT, 'reference/work-task-template.md');

  try {
    if (fs.existsSync(templateSrc) && !fs.existsSync(templateDest)) {
      fs.copyFileSync(templateSrc, templateDest);
    }
  } catch {
    // Silently ignore copy errors (matches bash behavior)
  }
}

// Set environment variable if not already set
const envFile = process.env.CLAUDE_ENV_FILE;
if (envFile && !process.env.SDD_ROOT_DIR) {
  try {
    fs.appendFileSync(envFile, `export SDD_ROOT_DIR="${SDD_ROOT}"\n`);
  } catch {
    // Silently ignore if we can't write to env file
  }
}

// ============================================================================
// Task List Detection (Tasks API Integration)
// ============================================================================

/**
 * Detect active ticket from session state files.
 * Session state files are written by /sdd:do-task and /sdd:do-all-tasks
 * to track active work.
 *
 * @param {string} sddRoot - Path to SDD root directory
 * @returns {string|null} - Ticket ID if found, null otherwise
 */
function detectTicketFromSessionState(sddRoot) {
  const stateDir = path.join(sddRoot, '.sdd-session-states');

  if (!fs.existsSync(stateDir)) {
    return null;
  }

  try {
    const files = fs.readdirSync(stateDir);
    const jsonFiles = files.filter((f) => f.endsWith('.json'));

    // Check each session state file for ticket_id
    for (const file of jsonFiles) {
      const filePath = path.join(stateDir, file);
      try {
        const content = fs.readFileSync(filePath, 'utf8');
        const data = JSON.parse(content);

        // Validate session state has ticket_id
        if (data && typeof data.ticket_id === 'string' && data.ticket_id) {
          // Extract just the ticket prefix (e.g., "TASKINT" from "TASKINT_description")
          const ticketId = data.ticket_id.split('_')[0];
          return ticketId;
        }
      } catch {
        // Invalid JSON or read error - skip this file
        continue;
      }
    }
  } catch {
    // Directory read error - fail silently
  }

  return null;
}

/**
 * Pattern to match unchecked "Task completed" checkbox in task files.
 * Matches: - [ ] **Task completed** or - [ ] Task completed
 */
const TASK_INCOMPLETE_PATTERN = /^[\s]*-\s*\[\s\]\s*\*{0,2}Task completed\*{0,2}/m;

/**
 * Detect active ticket by scanning tickets directory for uncompleted tasks.
 * This is a fallback when no session state file exists.
 *
 * @param {string} sddRoot - Path to SDD root directory
 * @returns {string|null} - Ticket ID if found, null otherwise
 */
function detectTicketFromTaskFiles(sddRoot) {
  const ticketsDir = path.join(sddRoot, 'tickets');

  if (!fs.existsSync(ticketsDir)) {
    return null;
  }

  try {
    const ticketDirs = fs.readdirSync(ticketsDir);

    for (const ticketDir of ticketDirs) {
      const tasksDir = path.join(ticketsDir, ticketDir, 'tasks');

      if (!fs.existsSync(tasksDir) || !fs.statSync(tasksDir).isDirectory()) {
        continue;
      }

      try {
        const taskFiles = fs.readdirSync(tasksDir);
        const mdFiles = taskFiles.filter(
          (f) => f.endsWith('.md') && !f.includes('_INDEX')
        );

        for (const taskFile of mdFiles) {
          const taskPath = path.join(tasksDir, taskFile);
          try {
            const content = fs.readFileSync(taskPath, 'utf8');

            // Check if task has unchecked "Task completed" checkbox
            if (TASK_INCOMPLETE_PATTERN.test(content)) {
              // Extract ticket ID prefix (e.g., "TASKINT" from "TASKINT_description")
              const ticketId = ticketDir.split('_')[0];
              return ticketId;
            }
          } catch {
            // Read error - skip this file
            continue;
          }
        }
      } catch {
        // Tasks dir read error - skip this ticket
        continue;
      }
    }
  } catch {
    // Tickets dir read error - fail silently
  }

  return null;
}

/**
 * Main task list detection function.
 * Detection priority:
 * 1. Session state files (authoritative for active work)
 * 2. Task file inspection fallback (for tickets with uncompleted tasks)
 *
 * @param {string} sddRoot - Path to SDD root directory
 * @returns {string|null} - Ticket ID for CLAUDE_TASK_LIST_ID, or null
 */
function detectActiveTicket(sddRoot) {
  // Priority 1: Check session state files
  const sessionTicket = detectTicketFromSessionState(sddRoot);
  if (sessionTicket) {
    return sessionTicket;
  }

  // Priority 2: Fallback to task file inspection
  return detectTicketFromTaskFiles(sddRoot);
}

// Only set CLAUDE_TASK_LIST_ID if SDD_TASKS_API_ENABLED is not 'false'
// (default is enabled)
if (process.env.SDD_TASKS_API_ENABLED !== 'false') {
  try {
    const activeTicket = detectActiveTicket(SDD_ROOT);

    if (activeTicket && envFile) {
      try {
        fs.appendFileSync(
          envFile,
          `export CLAUDE_TASK_LIST_ID="${activeTicket}"\n`
        );
      } catch {
        // Silently ignore if we can't write to env file
      }
    }
  } catch {
    // Task list detection errors should not block session start
    // Fail silently and allow the session to continue
  }
}

process.exit(0);
