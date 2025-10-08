# GitHub Workflow Testing Guide

This directory contains GitHub Actions workflows for automated testing of the OpenShift Network Debugger solution on a live OpenShift cluster.

## Workflow: test-openshift-solution.yml

### Purpose
Tests the complete OpenShift Network Debugger solution on a live OpenShift cluster, with special focus on validating that users with only namespace admin permissions can properly use the solution (with appropriate error handling for operations requiring cluster-admin).

### Required Secrets
The workflow requires two GitHub repository secrets to be configured:

1. **`OPENSHIFT_API`** - The OpenShift cluster API server URL (e.g., `https://api.cluster.example.com:6443`)
2. **`OPENSHIFT_TOKEN`** - A valid OpenShift authentication token with appropriate permissions

### Test Scenarios

#### 1. Basic Testing (`basic`)
- Validates script functionality and parameter validation
- Tests installation script
- Verifies command validation logic
- Checks RBAC configuration syntax

#### 2. Full Testing (`full`) - Default
- All basic tests plus:
- Actual tcpdump and ncat execution (if cluster-admin available)
- Comprehensive test suite execution
- Audit logging validation
- Performance and reliability testing

#### 3. Namespace Admin Only Testing (`namespace-admin-only`)
- Specifically tests the solution from a namespace admin perspective
- Validates appropriate error handling for operations requiring cluster-admin
- Ensures graceful degradation of functionality

### Manual Trigger
The workflow can be manually triggered with different test levels:

1. Go to the **Actions** tab in your GitHub repository
2. Select **Test OpenShift Network Debugger Solution**
3. Click **Run workflow**
4. Choose the test level:
   - `basic` - Quick validation of core functionality
   - `full` - Complete testing including actual command execution
   - `namespace-admin-only` - Focus on namespace admin access scenario

### Automatic Triggers
The workflow runs automatically on:
- Push to `main` branch
- Push to any `copilot/*` branch
- Pull requests targeting `main` branch

### Test Results

#### Artifacts
Each workflow run generates:
- **Test Report** (`test-report.md`) - Comprehensive results summary
- **Log Files** - Detailed execution logs for debugging

#### Test Validation Points
✅ **OpenShift Version Compatibility** - Ensures OpenShift 4.11+ support  
✅ **Permission Handling** - Validates cluster-admin vs namespace admin scenarios  
✅ **Script Functionality** - Tests parameter validation and command execution  
✅ **Security Validation** - Verifies command filtering and audit logging  
✅ **Error Handling** - Ensures graceful handling of permission limitations  
✅ **RBAC Configuration** - Validates role and binding configurations  

### Expected Behavior

#### With Cluster-Admin Permissions
- All tests should pass
- Actual network debugging commands execute successfully
- Full audit logging capabilities are validated

#### With Namespace Admin Only
- Scripts should detect insufficient permissions gracefully
- Appropriate error messages guide users to request cluster-admin access
- Basic validation and syntax checking still works

### Troubleshooting

#### Common Issues

**Authentication Failures**
```
Error: Login failed
```
- Verify `OPENSHIFT_API` and `OPENSHIFT_TOKEN` secrets are correctly set
- Ensure the token has not expired
- Check that the API server URL is accessible

**Permission Errors**
```
Error: cannot debug nodes
```
- Expected behavior for namespace admin testing
- For full testing, the token needs cluster-admin privileges

**Test Timeouts**
```
Error: Test timed out after 30 minutes
```
- Large clusters or network issues may cause timeouts
- Consider running `basic` test level first

### Integration with Development Workflow

#### Pre-PR Validation
The workflow runs on pull requests to validate changes before merging.

#### Continuous Validation
Automatic testing on pushes ensures the solution remains functional as the codebase evolves.

#### Multi-environment Testing
The same workflow can be configured with different OpenShift cluster secrets for testing across development, staging, and production-like environments.

### Security Considerations

- **Secrets Management**: OpenShift tokens are stored as GitHub encrypted secrets
- **Namespace Isolation**: Each test run creates a unique namespace to avoid conflicts
- **Cleanup**: Temporary resources are cleaned up after each test run
- **Token Scope**: Use service account tokens with minimal required permissions

### Extending the Tests

To add new test scenarios:

1. Add new test steps in the workflow file
2. Update the test report generation to include new results
3. Consider adding new test level options if needed

The workflow is designed to be extensible and can accommodate additional testing scenarios as the solution evolves.