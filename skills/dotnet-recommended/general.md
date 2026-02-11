# General Instructions

## Local Development

### Always format, build and test

For all dotnet projects, always run `dotnet format`, `dotnet build` and `dotnet test` after making code changes, and fix all issues.

**If build fails:**
- Fix all reported issues before completing the task
- Do not leave linting errors unfixed
- Re-run `dotnet test` until all checks pass

**Why:**
- Ensures consistent code formatting across the codebase
- Catches potential bugs and code quality issues early
- Maintains code quality standards
- Prevents style inconsistencies

---

## Database Migrations

### NEVER modify migration files manually

Migration files must **never** be edited by hand.

**Why:**
- Migrations are auto-generated
- Manual edits break the revision chain and cause deploy failures
- Migrations may already be applied to production databases

**Instead:**
- Modify model classes
- Run the migration

### NEVER delete migration files

Unless explicitly instructed by the user.

### Generate new migrations

When schema changes are needed:

---

## Coding Philosophy

### NO backwards compatibility

We do **NOT** favor backwards compatibility. Instead, we favor:

- **Features**: Build new functionality and improve the product
- **Proper cleanup**: Remove deprecated code, simplify architecture, eliminate technical debt
- **Fixing root causes**: When something breaks, fix the underlying issue rather than adding defensive programming

**Why:**
- Backwards compatibility adds complexity and technical debt
- Defensive programming hides real problems
- Clean, simple code is easier to maintain and debug
- If the program crashes, we fix the root cause, not sprinkle defensive code everywhere

**Examples of what NOT to do:**
- Fallback code paths for expected failures
- Maintaining deprecated APIs or functions for compatibility
- Defensive checks that hide real bugs

**Examples of what TO do:**
- Remove deprecated code paths immediately
- Simplify architecture by removing unnecessary abstraction layers
- Fix the root cause when errors occur, don't add workarounds

---

## General Rules

- **Read before edit**: Always read existing code before proposing changes
- **Preserve patterns**: Follow existing code style and conventions
- **Don't over-engineer**: Keep changes minimal and focused
- **Never push**: Never push to remote