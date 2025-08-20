# VALIDATE_LIST.md - Human Review & Sign-off

This VALIDATE_LIST.md file is for **human review and approval** after AI completes phases of work. The AI maintains its own detailed TODO.md in the `.ai-best-practices/` directory.

## Completed Phases Awaiting Review

### Phase: [Phase Name]
**Completed Date**: [YYYY-MM-DD]
**AI Summary**: 
- [What the AI accomplished]
- [Key decisions made]
- [Tests completed]

**Human Review Required**:
- [ ] Review code changes and commits
- [ ] Validate functionality and test results
- [ ] Check autonomous decisions in `.ai-best-practices/BESTJUDGEMENT.md`
- [ ] Review VALIDATION document for all changes
- [ ] Approve or request changes

**Status**: ⏳ Awaiting Human Review

---

## Future Phases (Approved by Human)

### Phase: [Next Phase Name]
**Description**: [Brief description of what needs to be done]
**Priority**: [High/Medium/Low]
**Assigned**: [AI/Human/Both]
**Status**: 📋 Ready for AI to Begin

---

## Archive (Completed & Approved)

### ✅ Phase: [Completed Phase Name]
**Completed**: [YYYY-MM-DD]
**Approved**: [YYYY-MM-DD]
**Summary**: [Brief summary of what was accomplished]

---

## Instructions for AI

### When Completing a Phase:
1. **Commit and tag** the phase completion
2. **Run all tests** to validate functionality
3. **Create VALIDATION document** explaining all changes and decisions
4. **Update this file** with completed phase in "Awaiting Review" section
5. **Reference `.ai-best-practices/BESTJUDGEMENT.md** for decision explanations
6. **Wait for human approval** before proceeding to next phase

### Phase-Based Review Process:
1. **Present each change individually** from VALIDATION document
2. **Explain purpose and reasoning** referencing BESTJUDGEMENT.md entries
3. **Apply human feedback** in separate post-review cleanup phase
4. **Repeat review cycle** until developer satisfied

## Instructions for Humans

1. **Review completed phases**: Check code, functionality, and AI decisions  
2. **Review `.ai-best-practices/BESTJUDGEMENT.md****: Validate autonomous decisions
3. **Move approved phases**: From "Awaiting Review" to "Archive" section
4. **Add future phases**: Define new phases in "Future Phases" section for AI to tackle
5. **Request cleanup**: Add post-review cleanup phases when needed 