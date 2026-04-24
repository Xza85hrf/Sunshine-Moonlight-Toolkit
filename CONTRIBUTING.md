# Contributing to Sunshine-Moonlight-Toolkit

Thank you for your interest in contributing! This project aims to make game streaming setup easier for everyone.

## How to Contribute

### Reporting Bugs

1. Check existing [issues](../../issues) to avoid duplicates
2. Use the bug report template
3. Include:
   - Windows version
   - PowerShell version (`$PSVersionTable.PSVersion`)
   - Sunshine/Moonlight versions
   - Steps to reproduce
   - Expected vs actual behavior

### Suggesting Features

1. Check existing [issues](../../issues) for similar suggestions
2. Use the feature request template
3. Describe the use case and benefits

### Submitting Code

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test thoroughly on Windows 10/11
5. Commit with clear messages (`git commit -m 'Add amazing feature'`)
6. Push to your branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Code Style Guidelines

### PowerShell Scripts

- Use `[CmdletBinding()]` for all scripts
- Include `.SYNOPSIS`, `.DESCRIPTION`, and `.EXAMPLE` help blocks
- Use approved PowerShell verbs (Get, Set, Test, etc.)
- Handle errors gracefully with try/catch
- Provide colored output for user feedback:
  - Green: Success
  - Yellow: Warning
  - Red: Error
  - Cyan: Information
- Test on both Windows 10 and Windows 11

### Batch Files

- Keep batch files simple (launcher only)
- Use meaningful labels and comments

### Documentation

- Update README.md if adding features
- Add inline comments for complex logic
- Update CHANGELOG.md

## Testing Checklist

Before submitting:

- [ ] Tested on Windows 10
- [ ] Tested on Windows 11 (if available)
- [ ] Tested with Sunshine installed
- [ ] Tested with Moonlight installed
- [ ] Tested with and without Tailscale
- [ ] Works without admin rights (except where noted)
- [ ] No hardcoded personal information (IPs, paths, etc.)

## Questions?

Open an issue with the "question" label.

Thank you for helping improve game streaming for everyone!
