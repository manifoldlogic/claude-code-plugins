# Ticket Naming Guidelines

This document defines the naming conventions for tickets in the `${SDD_ROOT_DIR}/` directory structure.

## Format

```
{TICKET_ID}_{descriptive-name}
```

**Components:**
- **TICKET_ID**: UPPERCASE ticket identifier (2-12 characters, may include dashes for Jira IDs)
- **Separator**: Single underscore `_`
- **descriptive-name**: lowercase-with-dashes description

## Requirements

### TICKET_ID Component
- **Length**: 2-12 characters
- **Case**: UPPERCASE only (letters and numbers)
- **Dashes**: Allowed for Jira-style IDs (e.g., `UIT-9819`)
- **Purpose**: Matches ticket prefix for easy association (often a Jira ticket ID)
- **Uniqueness**: Must be unique across all tickets (active and archived)
- **Clarity**: Should hint at ticket area when possible

**Good Examples:**
- `DKRHUB` - Docker Hub (custom identifier)
- `LOCAL` - Local deployment (custom identifier)
- `MCPSTART` - MCP startup (custom identifier)
- `MPEMBED` - Multi-provider embeddings (custom identifier)
- `UIT-9819` - Jira ticket ID (user interface task)
- `PROJ-123` - Jira ticket ID (project task)
- `BE-4567` - Jira ticket ID (backend task)

**Bad Examples:**
- `D` - Too short (minimum 2 characters)
- `DOCKERHUBPUBLISHING` - Too long (maximum 12 characters)
- `docker` - Wrong case (must be uppercase)
- `DKR_HUB` - No underscores in ticket-id (use dashes for Jira-style IDs)
- `uit-9819` - Wrong case (must be uppercase)

### descriptive-name Component
- **Case**: lowercase only
- **Separator**: Hyphens `-` between words
- **Length**: 2-5 words typically
- **Clarity**: Should be immediately understandable
- **Specificity**: Specific enough to distinguish from similar tickets

**Good Examples:**
- `docker-hub-publishing`
- `local-deployment`
- `mcp-provider-startup-fix`
- `hybrid-retrieval-system`

**Bad Examples:**
- `dockerhubpublishing` - No separators
- `Docker-Hub-Publishing` - Wrong case
- `docker_hub_publishing` - Wrong separator (underscores)
- `stuff` - Too vague
- `a-really-long-description-with-many-unnecessary-words` - Too long

## Benefits of This Format

### 1. Self-Documenting Paths
```bash
# Clear what this is without opening it
${SDD_ROOT_DIR}/tickets/DKRHUB_docker-hub-publishing/

# vs unclear short code
${SDD_ROOT_DIR}/tickets/DKRHUB/
```

### 2. Better Searchability
```bash
# Find all Docker-related tickets
ls -d ${SDD_ROOT_DIR}/tickets/*docker* ${SDD_ROOT_DIR}/archive/tickets/*docker*

# Find embedding-related tickets
ls -d ${SDD_ROOT_DIR}/**/tickets/*embed*
```

### 3. AI Agent Comprehension
AI agents can immediately understand ticket purpose from the path alone, without needing to read README files.

### 4. Ticket Association
Tasks still use the ticket-id with dot separator:
- Folder: `DKRHUB_docker-hub-publishing/`
- Tasks: `DKRHUB.1001_setup.md`, `DKRHUB.1002_implementation.md`

For Jira-style ticket IDs:
- Folder: `UIT-9819_user-profile-update/`
- Tasks: `UIT-9819.1001_analysis.md`, `UIT-9819.1002_implementation.md`

## Examples by Category

### Custom Ticket IDs (Generated/Project-Specific)

#### Infrastructure
- `DKRHUB_docker-hub-publishing`
- `LOCAL_local-deployment`
- `CICD_continuous-integration`

#### Features
- `HYBRID_hybrid-retrieval-system`
- `MPEMBED_multi-provider-embeddings`
- `CONTEXT_context-assembly-engine`

#### Improvements
- `PERF_performance-optimization`
- `QUALITY_code-quality-improvements`
- `SECAUDIT_security-audit`

#### Bug Fixes
- `MCPSTART_mcp-provider-startup-fix`
- `HOOKFIX_misc-fixes`
- `AUTHFIX_authentication-bug-fix`

### Jira-Based Ticket IDs (From External Tracker)

When your ticket corresponds to a Jira story, bug, or task, use the Jira ticket ID directly:

#### User Interface Tasks
- `UIT-9819_user-profile-update`
- `UIT-1234_dashboard-redesign`
- `UIT-5678_mobile-responsive-fix`

#### Backend Tasks
- `BE-4567_api-endpoint-optimization`
- `BE-8901_database-migration`
- `BE-2345_cache-implementation`

#### Project/Epic Tasks
- `PROJ-123_authentication-overhaul`
- `PROJ-456_payment-integration`

#### Bug Tickets
- `BUG-789_login-session-timeout`
- `BUG-012_data-sync-error`

### Language Support (Custom IDs)
- `LANGPARSE_multi-language-support`
- `MDENHANCE_markdown-enhancement`
- `PYPARSER_python-parser-integration`

## Creating a New Ticket

### Step 1: Choose a TICKET_ID

**Option A: Use a Jira Ticket ID (Recommended when applicable)**
1. If this work corresponds to a Jira story/bug/task, use that ID directly
2. Examples: `UIT-9819`, `BE-4567`, `PROJ-123`
3. This creates a 1:1 mapping with your external tracker

**Option B: Create a Custom Identifier**
1. Review existing ticket-ids in `${SDD_ROOT_DIR}/tickets/` and `${SDD_ROOT_DIR}/archive/tickets/`
2. Choose a unique, memorable ticket-id (2-12 chars)
3. Use abbreviations that make sense in your domain

### Step 2: Write descriptive-name

1. Think: "What is this ticket doing?"
2. Use 2-5 words
3. Use lowercase and hyphens
4. Be specific and clear

### Step 3: Verify Format

Check your name against these rules:
```bash
# Pattern to match (supports both custom and Jira-style IDs)
^[A-Z][A-Z0-9]*(-[A-Z0-9]+)*_[a-z][a-z0-9-]*[a-z0-9]$

# Valid examples - Custom IDs
DKRHUB_docker-hub-publishing  ✓
LOCAL_local-deployment        ✓
MPEMBED_multi-provider-embed  ✓

# Valid examples - Jira-style IDs
UIT-9819_user-profile-update  ✓
BE-4567_api-optimization      ✓
PROJ-123_auth-overhaul        ✓
BUG-789_login-fix             ✓

# Invalid examples
dkrhub_docker-hub             ✗ (lowercase ticket-id)
DKRHUB-docker-hub             ✗ (wrong separator between ID and name - must be underscore)
DKRHUB_Docker-Hub             ✗ (uppercase in description)
D_docker-hub-publishing       ✗ (ticket-id too short - minimum 2 chars)
VERYLONGTICKETID_name         ✗ (ticket-id too long - maximum 12 chars)
uit-9819_user-profile         ✗ (lowercase Jira ID - must be uppercase)
```

**Important distinction:**
- Dashes IN ticket-id are OK: `UIT-9819` ✓ (Jira-style)
- Dash BETWEEN ticket-id and name is NOT OK: `DKRHUB-docker` ✗ (must use underscore)

### Step 4: Create Structure

```bash
mkdir -p ${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{descriptive-name}/{planning,tasks}
```

### Step 5: Update Documentation

Add your ticket to:
- `${SDD_ROOT_DIR}/tickets/README.md` (if active)
- `${SDD_ROOT_DIR}/archive/README.md` (when archived)

## Renaming Existing Tickets

If you need to rename an existing ticket:

1. **Rename folder:**
   ```bash
   mv ${SDD_ROOT_DIR}/tickets/{OLD} ${SDD_ROOT_DIR}/tickets/{TICKET_ID}_{descriptive-name}
   ```

2. **Update references in:**
   - `${SDD_ROOT_DIR}/README.md`
   - `${SDD_ROOT_DIR}/tickets/README.md` or `${SDD_ROOT_DIR}/archive/README.md`
   - Any documentation that links to the ticket

3. **Do NOT rename tasks** - they keep their original `{TICKET_ID}.NNN` format

## Anti-Patterns to Avoid

### ❌ Generic Names
- `WORK_things`
- `MISC_various`

Use specific, descriptive names instead.

### ❌ Redundant Words
- `TICKET_ticket-name` (redundant "ticket")
- `FEATURE_feature-name` (redundant "feature")

The structure already indicates it's a ticket.

### ❌ Implementation Details
- `DOCKER_using-compose-and-swarm` (too specific)
- `EMBED_openai-and-ollama-providers` (might change)

Focus on the goal, not the implementation.

### ❌ Version Numbers
- `SEARCH_v2-hybrid-search` (versions should be in git)
- `API_new-api-design` (avoid "new", "old")

Tickets should describe their purpose, not their iteration.

## FAQ

**Q: What if my TICKET_ID is already taken?**
A: Choose a different ticket-id. Add numbers if needed: `MCP2`, `AUTH2`, or use a more specific abbreviation.

**Q: Can I use a Jira ticket ID?**
A: Yes! This is actually preferred when your work corresponds to a Jira ticket. Use the Jira ID directly: `UIT-9819`, `BE-4567`, `PROJ-123`. This creates a 1:1 mapping with your external tracker.

**Q: Can I use numbers in the TICKET_ID?**
A: Yes. Numbers are common in Jira IDs (`UIT-9819`) and useful for disambiguation: `LOCAL2`, `MCP3`.

**Q: Can dashes appear in the TICKET_ID?**
A: Yes, for Jira-style IDs like `UIT-9819` or `BE-4567`. The dash is part of the ID. However, do NOT use dashes as the separator between ticket-id and descriptive-name (use underscore for that).

**Q: Can I use numbers in descriptive-name?**
A: Yes, if meaningful: `http2-support`, `oauth2-integration`.

**Q: Should I include the parent ticket name?**
A: Only if it adds clarity: `APIV2_search-optimization` is better than `SEARCH_optimization` if there are multiple search systems.

**Q: How specific should descriptive-name be?**
A: Specific enough to distinguish from similar tickets, but general enough to encompass the full scope.

**Q: What if the ticket scope changes?**
A: Rename the folder and update documentation. Better to have accurate names than historical ones.

## Enforcement

These guidelines should be followed for:
- ✅ All new tickets
- ✅ Tickets being moved to archive
- ⚠️ Existing tickets (rename during maintenance)

## Related Documents

- [Work Ticket Template](./work-task-template.md) - Ticket naming follows the TICKET_ID
- [Spec-Driven Development](./spec-driven-development.md) - Process from vision to tickets
- [.agents README](../README.md) - Overall directory structure
