#!/usr/bin/env node

/**
 * SDD Plugin - Environment Setup Hook
 * This hook runs at session start to:
 * 1. Set SDD_ROOT_DIR environment variable
 * 2. Create directory structure if not exists
 * 3. Copy reference templates to data directory
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

process.exit(0);
