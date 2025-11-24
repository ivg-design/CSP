# Contributing to CSP (CLI Sidecar Protocol)

Thank you for your interest in contributing to CSP! This project represents foundational infrastructure for multi-agent CLI orchestration.

## 🚀 Getting Started

### Prerequisites
- Python 3.8+
- Node.js 16+ (for gateway components)
- Basic understanding of PTY, terminal emulation, and CLI tools

### Quick Setup
```bash
git clone https://github.com/ivg-design/CSP.git
cd CSP
python3 src/csp_sidecar.py --help
```

## 📋 Development Guidelines

### Code Style
- **Python**: Follow PEP 8, use type hints where appropriate
- **Shell Scripts**: Use bash with proper error handling
- **Documentation**: Clear, comprehensive markdown

### Testing
- Test with multiple CLI agents (Claude, Codex, Gemini)
- Verify native CLI experience preservation
- Test flow control under various load conditions

### Architecture Principles
1. **Non-invasive**: Never corrupt native CLI experience
2. **Intelligent**: Use context-aware timing for safe injection
3. **Resilient**: Handle edge cases gracefully
4. **Extensible**: Design for easy enhancement

## 🔧 Areas for Contribution

### High Priority
- **Gateway Implementation**: Node.js/Express server component
- **Human Interface**: Browser-based command center
- **Agent Connectors**: Specialized connectors for different CLI tools
- **Documentation**: Usage examples, tutorials, API docs

### Medium Priority
- **Enhanced Flow Control**: Advanced state detection
- **Monitoring Dashboard**: Real-time system metrics
- **Configuration Management**: YAML/JSON config system
- **Cross-platform Support**: Windows/macOS compatibility

### Future Features
- **Collaborative Pause**: Multi-agent coordination
- **Smart Batching**: Message efficiency optimization
- **Learning System**: Adaptive timing based on agent behavior
- **Plugin Architecture**: Extensible agent support

## 🐛 Bug Reports

### Before Reporting
- Check existing issues for duplicates
- Test with the latest version
- Reproduce with minimal example

### Include in Your Report
- CSP version and commit hash
- Operating system and terminal emulator
- CLI agents being used
- Full error output or unexpected behavior
- Steps to reproduce

## 💡 Feature Requests

We welcome feature requests! Please:
- Check if it aligns with project goals
- Describe the use case clearly
- Consider implementation complexity
- Propose API design if applicable

## 📝 Documentation

### Current Documentation
- `docs/current/LLMGroupChat.md` - Main implementation guide
- `docs/architecture/` - System design specifications
- `docs/analysis/` - Implementation analysis and fixes

### Documentation Standards
- Clear, actionable instructions
- Include code examples
- Update when making changes
- Consider different user levels

## 🔄 Development Workflow

### Branch Naming
- `feature/description` - New features
- `fix/description` - Bug fixes
- `docs/description` - Documentation updates
- `refactor/description` - Code improvements

### Commit Messages
Follow the established pattern:
```
Brief summary of changes

## Details
- Specific change 1
- Specific change 2

## Technical Notes
- Implementation details
- Performance considerations
- Breaking changes (if any)

🤖 Generated with [Claude Code](https://claude.ai/code)
Co-Authored-By: Claude <noreply@anthropic.com>
```

### Pull Request Process
1. Fork the repository
2. Create feature branch
3. Make changes with tests
4. Update documentation
5. Submit PR with clear description

## 🏗️ Project Structure

```
src/              # Production code
docs/current/     # Latest documentation
docs/architecture/# System specifications
docs/analysis/    # Implementation analysis
docs/planning/    # Design documents
.archive/         # Historical implementations
```

## 🤝 Community

### Communication
- GitHub Issues for bugs and feature requests
- GitHub Discussions for general questions
- Pull Requests for code contributions

### Code of Conduct
- Be respectful and inclusive
- Focus on technical merit
- Help others learn and contribute
- Maintain professional communication

## 🎯 Success Criteria

### Quality Standards
- **Reliability**: No corruption of native CLI experience
- **Performance**: Minimal latency impact (<50ms)
- **Compatibility**: Works with major CLI tools
- **Documentation**: Clear setup and usage guides

### Review Process
- Code review by maintainers
- Testing with real-world scenarios
- Documentation review
- Performance impact assessment

## 📞 Getting Help

### Quick Questions
- Check existing documentation first
- Search GitHub Issues
- Create new issue with "question" label

### Complex Discussions
- Use GitHub Discussions
- Provide context and use cases
- Be specific about requirements

---

**Thank you for contributing to CSP!** Your efforts help advance the field of multi-agent CLI orchestration.

*This project aims to become the foundational infrastructure for LLM agent collaboration in terminal environments.*