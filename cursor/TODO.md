# TODO List

## High Priority
- [ ] Add command-line argument support for verbosity control
- [ ] Add support for multiple Git hosts (GitLab, Bitbucket, etc.)
- [ ] Implement automatic HTTPS to SSH conversion
- [ ] Add support for custom submodule configurations
- [ ] Create installation script for setting up symlinks and permissions

## Extension Development
- [ ] **PRIORITY**: Investigate duplicate files issue in node_modules preventing VSIX packaging
  - Files with same case insensitive paths in @types/sarif and @types/normalize-package-data
  - Error: "The following files have the same case insensitive path, which isn't supported by the VSIX format"
  - May need to update package.json excludes or clean up dependencies
  - Check after running clean rebuild script to see if issue persists
- [ ] Add extension development mode with hot reload
- [ ] Create extension testing framework
- [ ] Add extension configuration options
- [ ] Implement extension update mechanism

## Medium Priority
- [ ] Add support for custom Git hooks
- [ ] Implement repository template support
- [ ] Add support for multiple AI best practices repositories
- [ ] Create backup system for repository health checks
- [ ] Add support for custom logging destinations

## Low Priority
- [ ] Add support for repository statistics
- [ ] Implement repository cleanup tools
- [ ] Add support for custom Git configurations
- [ ] Create documentation generator
- [ ] Add support for repository templates

## Documentation
- [ ] Add detailed installation instructions
- [ ] Create troubleshooting guide
- [ ] Add examples for common use cases
- [ ] Create contribution guidelines
- [ ] Add API documentation

## Testing
- [ ] Create test suite for script functionality
- [ ] Add integration tests with Cursor IDE
- [ ] Create test environment setup script
- [ ] Add performance benchmarks
- [ ] Create test documentation

## Maintenance
- [ ] Set up automated testing
- [ ] Create release process
- [ ] Add version management
- [ ] Create update mechanism
- [ ] Add error reporting system 